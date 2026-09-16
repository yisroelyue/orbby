import { AgentSession } from './session.js';
import { executeToolCalls } from './tool-scheduler.js';
import { streamComplete, complete } from '../llm/client.js';
import { toPlainText, toUserContent } from '../llm/content-adapter.js';
import { extractAttachments } from '../llm/attachment-extractor.js';
import { AGENT_SYSTEM_PROMPT } from './system-prompt.js';
import { homedir } from 'node:os';
import { join } from 'node:path';
function defaultWorkspacePath() { return join(homedir(), 'Desktop'); }
export class AgentRuntime {
    registry;
    sessions = new Map();
    constructor(registry) {
        this.registry = registry;
    }
    session(id) { let value = this.sessions.get(id); if (!value) {
        value = new AgentSession(id);
        this.sessions.set(id, value);
    } return value; }
    async chat(sessionId, message, attachments, config, onEvent, signal, history = [], askUser, permissionMode = 'ask') {
        const session = this.session(sessionId);
        return session.runExclusive(async () => {
            session.turn++;
            session.step = 0;
            session.append('turn/start', { message });
            onEvent('turn.start', { turn: session.turn });
            // 历史轮只回放文本（多模态块经 toPlainText 归一化），图片仅当前轮发送
            if (session.messages.length === 0 && history.length)
                session.messages.push(...history.map(item => ({ role: item.role, content: toPlainText(item.content) })));
            session.messages.push({ role: 'system', content: AGENT_SYSTEM_PROMPT });
            if (config.systemPrompt || config.usageRules || config.personality) {
                const configuredPersonality = config.systemPrompt?.match(/\[personality:(humor|serious|concise)\]/)?.[1] ?? config.personality ?? 'humor';
                const personality = configuredPersonality === 'serious' ? '严谨、专业、克制，避免玩梗。' : configuredPersonality === 'concise' ? '简洁直接，优先给出结论，避免冗余。' : '风格幽默，可以使用适量网络热词热梗；不刻意讨好，保持自己的性格。';
                const custom = [config.systemPrompt, config.usageRules ? `使用规范：\n${config.usageRules}` : '', `当前性格：${personality}`].filter(Boolean).join('\n\n');
                session.messages.push({ role: 'system', content: custom });
            }
            // 文本/PDF 附件先在 Node 侧提取为文本，再统一多模态组装（图片在前、文字在后）
            await extractAttachments(attachments, signal);
            session.messages.push({ role: 'user', content: toUserContent(message, attachments) });
            for (let iteration = 1; iteration <= 30; iteration++) {
                signal.throwIfAborted();
                session.step = iteration;
                session.append('step/start');
                onEvent('step.start', { turn: session.turn, step: iteration });
                const response = await streamComplete(config, session.messages, this.registry.definitions().map(tool => ({ type: 'function', function: tool })), signal, text => onEvent('llm.token', { text }));
                session.messages.push({ role: 'assistant', content: response.content, ...(response.toolCalls.length ? { tool_calls: response.toolCalls.map(call => ({ id: call.id, type: 'function', function: { name: call.name, arguments: JSON.stringify(call.arguments) } })) } : {}) });
                if (response.content)
                    session.append('assistant/message', { content: response.content });
                if (!response.toolCalls.length) {
                    session.append('step/end', { reason: 'completed' });
                    onEvent('step.end', { reason: 'completed' });
                    session.append('turn/end', { reason: 'completed' });
                    onEvent('turn.end', { reason: 'completed' });
                    return response.content;
                }
                const { WorkspacePermissionService } = await import('../services/workspace-permission.js');
                const workspacePath = process.env.ORBBY_WORKSPACE ?? defaultWorkspacePath();
                const permissions = new WorkspacePermissionService();
                permissions.setMode(permissionMode);
                const results = await executeToolCalls(this.registry, response.toolCalls, { workspacePath, sessionId, requestId: '', permissionMode: 'accept', askUser, permissions }, signal, 4, onEvent);
                for (const result of results)
                    session.messages.push({ role: 'tool', content: result.error ? `Error: ${result.error.message}` : serializeToolResult(result.output), tool_call_id: result.id });
                session.append('step/end', { reason: 'tool_calls' });
                onEvent('step.end', { reason: 'tool_calls' });
            }
            throw new Error('Agent exceeded maximum iterations');
        });
    }
    reset(sessionId) { this.sessions.delete(sessionId); }
    async compact(sessionId, config) {
        const session = this.session(sessionId);
        return session.runExclusive(async () => {
            if (!session.messages.length)
                return '当前会话没有可压缩的上下文。';
            const source = session.messages
                .filter(message => message.role !== 'system')
                .map(message => `${message.role}: ${toPlainText(message.content)}`)
                .join('\n');
            if (!source.trim())
                return '当前会话没有可压缩的参与者对话。';
            const response = await complete(config, [{ role: 'system', content: '你是会话上下文压缩器。只摘要参与者对话中的事实、用户目标、已确认决定、实际文件改动和待办事项。不要摘要或改写系统下发的角色设定、行为约束、使用规范或其他系统消息；这些内容由系统提示词负责。只输出摘要。' }, { role: 'user', content: source }], [], new AbortController().signal);
            const summary = response.content.trim();
            if (!summary)
                throw new Error('压缩器返回了空摘要');
            session.messages.splice(0, session.messages.length, { role: 'system', content: `以下是此前会话的压缩摘要：\n${summary}` });
            session.append('context/compact', { messageCount: session.messages.length, summary });
            return summary;
        });
    }
    stats(sessionId) {
        const s = this.session(sessionId);
        const contextChars = s.messages.reduce((total, message) => total + toPlainText(message.content).length, 0);
        const totalTokens = Math.ceil(contextChars / 4);
        const maxTokens = 32000;
        const compactEvents = s.events.filter(event => event.type === 'context/compact');
        return { sessionId, messageCount: s.messages.length, eventCount: s.events.length, contextChars, totalTokens, maxTokens, usagePercent: Math.round(totalTokens / maxTokens * 100), turn: s.turn, step: s.step, lastCompactionAt: compactEvents.at(-1)?.at ?? null };
    }
    tools() { return this.registry.definitions(); }
    async executeTools(sessionId, requestId, calls, signal, onEvent) { return executeToolCalls(this.registry, calls, { workspacePath: process.env.ORBBY_WORKSPACE ?? defaultWorkspacePath(), sessionId, requestId, permissionMode: 'accept' }, signal, 4, onEvent); }
}
function serializeToolResult(value) {
    if (typeof value === 'string')
        return value;
    try {
        return JSON.stringify(value);
    }
    catch {
        return String(value);
    }
}
