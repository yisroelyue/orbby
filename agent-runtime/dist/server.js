import { WebSocketServer, WebSocket } from 'ws';
import { reply } from './protocol.js';
import { ToolRegistry } from './tools/types.js';
import { sanitizeAttachments } from './llm/content-adapter.js';
import { AgentRuntime } from './agent/runtime.js';
import { registerFilesystemTools } from './tools/fs-tools.js';
import { registerShellTools } from './tools/shell-tools.js';
import { registerTerminalTools } from './tools/terminal-tools.js';
import { registerSkillTools } from './tools/skill-tools.js';
import { registerAskUserTool } from './tools/ask-user.js';
import { conversationLog } from './conversation-log.js';
import { loadPermissionMode, savePermissionMode } from './services/permission-storage.js';
import { clearSkillCache, startSkillsWatch } from './services/skill-service.js';
let permissionMode = loadPermissionMode();
export function startServer(port = Number(process.env.ORBBY_AGENT_PORT ?? 43127)) {
    const registry = new ToolRegistry();
    registerFilesystemTools(registry);
    registerShellTools(registry);
    registerTerminalTools(registry);
    registerSkillTools(registry);
    registerAskUserTool(registry);
    const agent = new AgentRuntime(registry);
    const wss = new WebSocketServer({ host: '127.0.0.1', port });
    // 技能目录监听：任何文件变化（LLM 创建技能/用户手改）自动清缓存并广播，
    // Flutter 收到 skills.changed 静默重扫面板——等效自动 /reload-skill，
    // 创建/修改技能后立即可 @ 引用，无需手动命令或重启
    startSkillsWatch(() => {
        clearSkillCache();
        for (const client of wss.clients)
            send(client, { type: 'skills.changed' });
    });
    // active/answers 按连接隔离：断连时只清理本连接的挂起请求，不误伤其他连接
    wss.on('connection', socket => {
        const active = new Map();
        const answers = new Map();
        // 断连期间错过的目录变化，在重连建立时补一次通知（重扫幂等，无变化时无害）
        send(socket, { type: 'skills.changed' });
        socket.on('message', raw => void handle(socket, agent, active, answers, JSON.parse(raw.toString())));
        socket.on('close', () => {
            for (const [questionId, entry] of answers) {
                entry.reject(new Error('connection closed'));
                answers.delete(questionId);
            }
            for (const controller of active.values())
                controller.abort(new Error('connection closed'));
            active.clear();
        });
    });
    wss.on('listening', () => console.log(JSON.stringify({ status: 'ready', port, protocolVersion: 1 })));
    return wss;
}
async function handle(socket, agent, active, answers, message) {
    const sessionId = 'sessionId' in message ? message.sessionId : undefined;
    const conversationId = (message.payload)?.conversationId;
    void conversationLog(conversationId, 'request', message);
    try {
        if (message.type === 'hello')
            return send(socket, reply('hello.ok', message.requestId, undefined, { protocolVersion: 1 }));
        if (message.type === 'permission.mode') {
            const mode = String(message.payload?.mode ?? 'ask');
            if (mode === 'ask' || mode === 'read' || mode === 'all') {
                permissionMode = mode;
                savePermissionMode(mode);
                if (mode === 'ask') {
                    const permissions = new (await import('./services/workspace-permission.js')).WorkspacePermissionService();
                    await permissions.clear();
                }
            }
            return send(socket, reply('permission.mode.accepted', message.requestId, sessionId));
        }
        if (message.type === 'permission.status')
            return send(socket, reply('permission.status', message.requestId, sessionId, { mode: permissionMode }));
        // /cd 工作区切换：按会话隔离（多会话并发时互不影响）；set 校验失败（目录不存在）走外层 catch 回 agent.error
        if (message.type === 'workspace.get')
            return send(socket, reply('workspace.status', message.requestId, sessionId, { workspace: agent.getWorkspace(sessionId ?? 'default') }));
        if (message.type === 'workspace.set') {
            const workspace = await agent.setWorkspace(sessionId ?? 'default', String(message.payload.path ?? ''));
            return send(socket, reply('workspace.status', message.requestId, sessionId, { workspace }));
        }
        // /reload-skill：清技能缓存（面板侧重扫由 Flutter 完成），下次引用展开时重扫
        if (message.type === 'skills.reload') {
            clearSkillCache();
            return send(socket, reply('skills.status', message.requestId, sessionId, { reloaded: true }));
        }
        if (message.type === 'user.answer') {
            const entry = answers.get(message.payload.questionId);
            if (entry) {
                answers.delete(message.payload.questionId);
                entry.resolve(message.payload.answers);
                void conversationLog(conversationId, 'event', { type: 'user.answer', payload: { questionId: message.payload.questionId, answers: message.payload.answers } });
            }
            return send(socket, reply('user.answer.accepted', message.requestId, sessionId));
        }
        if (message.type === 'chat.start') {
            const controller = new AbortController();
            active.set(message.requestId, controller);
            const cfg = message.payload.llm ?? {};
            // 附件经 Node 侧兜底校验（数量/mime/大小），Flutter 已限一层
            const attachments = sanitizeAttachments(message.payload.attachments);
            const askUser = (questions) => new Promise((resolve, reject) => { const questionId = `question-${Date.now()}-${Math.random().toString(16).slice(2)}`; answers.set(questionId, { requestId: message.requestId, resolve, reject }); void conversationLog(conversationId, 'event', { type: 'user.question', payload: { questionId, questions } }); send(socket, reply('user.question', message.requestId, sessionId, { questionId, questions })); });
            const result = await agent.chat(sessionId, message.payload.message, attachments, { url: String(cfg.url ?? ''), apiKey: String(cfg.apiKey ?? ''), model: String(cfg.model ?? ''), platform: String(cfg.platform ?? ''), systemPrompt: String(cfg.systemPrompt ?? ''), usageRules: String(cfg.usageRules ?? ''), conversationId }, (type, payload) => { if (type !== 'llm.token')
                void conversationLog(conversationId, 'event', { type, payload }); send(socket, reply(type === 'llm.token' ? 'agent.token' : type, message.requestId, sessionId, payload)); }, controller.signal, message.payload.history ?? [], askUser, permissionMode);
            active.delete(message.requestId);
            return send(socket, reply('agent.done', message.requestId, sessionId, { content: result }));
        }
        if (message.type === 'chat.cancel') {
            active.get(message.requestId)?.abort(new Error('cancelled'));
            // reject 挂起中的提问，让卡在 await askUser 的工具 worker 走 TOOL_ERROR 退出，避免会话锁死
            for (const [questionId, entry] of answers)
                if (entry.requestId === message.requestId) {
                    entry.reject(new Error('user question cancelled'));
                    answers.delete(questionId);
                }
            return send(socket, reply('agent.cancelled', message.requestId, sessionId));
        }
        if (message.type === 'session.reset')
            agent.reset(sessionId);
        if (message.type === 'agent.compact') {
            const cfg = message.payload?.llm ?? {};
            const content = await agent.compact(sessionId, { url: String(cfg.url ?? ''), apiKey: String(cfg.apiKey ?? ''), model: String(cfg.model ?? ''), platform: String(cfg.platform ?? ''), systemPrompt: String(cfg.systemPrompt ?? ''), usageRules: String(cfg.usageRules ?? '') });
            return send(socket, reply('agent.done', message.requestId, sessionId, { content }));
        }
        if (message.type === 'session.stats')
            return send(socket, reply('session.stats', message.requestId, sessionId, agent.stats(sessionId)));
        if (message.type === 'tools.list')
            return send(socket, reply('tools.list', message.requestId, sessionId, { tools: agent.tools() }));
        send(socket, reply('ack', message.requestId, sessionId));
    }
    catch (error) {
        active.delete(message.requestId);
        const value = error;
        send(socket, { type: 'agent.error', requestId: message.requestId, sessionId, error: { code: value.code ?? 'INTERNAL_ERROR', message: error instanceof Error ? error.message : String(error) } });
    }
}
function send(socket, value) { if (socket.readyState === WebSocket.OPEN)
    socket.send(JSON.stringify(value)); }
