import { WebSocketServer, WebSocket } from 'ws';
import { ClientMessage, AgentQuestion, reply } from './protocol.js';
import { ToolRegistry } from './tools/types.js';
import { AgentRuntime } from './agent/runtime.js';
import { registerFilesystemTools } from './tools/fs-tools.js';
import { registerShellTools } from './tools/shell-tools.js';
import { registerTerminalTools } from './tools/terminal-tools.js';
import { registerSkillTools } from './tools/skill-tools.js';
import { registerAskUserTool } from './tools/ask-user.js';
import { conversationLog } from './conversation-log.js';

/** 挂起中的用户提问：cancel/断连时经 reject 唤醒卡在 await 上的工具 worker */
type PendingQuestion = { requestId: string; resolve: (value: string[][]) => void; reject: (error: Error) => void };

export function startServer(port = Number(process.env.ORBBY_AGENT_PORT ?? 43127)) {
  const registry = new ToolRegistry();
  registerFilesystemTools(registry);
  registerShellTools(registry);
  registerTerminalTools(registry);
  registerSkillTools(registry);
  registerAskUserTool(registry);
  const agent = new AgentRuntime(registry);
  const wss = new WebSocketServer({host: '127.0.0.1', port});
  // active/answers 按连接隔离：断连时只清理本连接的挂起请求，不误伤其他连接
  wss.on('connection', socket => {
    const active = new Map<string, AbortController>();
    const answers = new Map<string, PendingQuestion>();
    socket.on('message', raw => void handle(socket, agent, active, answers, JSON.parse(raw.toString()) as ClientMessage));
    socket.on('close', () => {
      for (const [questionId, entry] of answers) { entry.reject(new Error('connection closed')); answers.delete(questionId); }
      for (const controller of active.values()) controller.abort(new Error('connection closed'));
      active.clear();
    });
  });
  wss.on('listening', () => console.log(JSON.stringify({status:'ready', port, protocolVersion:1})));
  return wss;
}

async function handle(socket: WebSocket, agent: AgentRuntime, active: Map<string, AbortController>, answers: Map<string, PendingQuestion>, message: ClientMessage) {
  const sessionId = 'sessionId' in message ? message.sessionId : undefined;
  const conversationId = ((message as any).payload)?.conversationId as string | undefined;
  void conversationLog(conversationId, 'request', message);
  try {
    if (message.type === 'hello') return send(socket, reply('hello.ok', message.requestId, undefined, {protocolVersion:1}));
    if (message.type === 'user.answer') {
      const entry = answers.get(message.payload.questionId);
      if (entry) { answers.delete(message.payload.questionId); entry.resolve(message.payload.answers); void conversationLog(conversationId, 'event', {type:'user.answer', payload:{questionId:message.payload.questionId, answers:message.payload.answers}}); }
      return send(socket, reply('user.answer.accepted', message.requestId, sessionId));
    }
    if (message.type === 'chat.start') {
      const controller = new AbortController(); active.set(message.requestId, controller);
      const cfg = (message.payload as any).llm ?? {};
      const askUser = (questions: AgentQuestion[]) => new Promise<string[][]>((resolve, reject) => { const questionId=`question-${Date.now()}-${Math.random().toString(16).slice(2)}`; answers.set(questionId,{requestId:message.requestId,resolve,reject}); void conversationLog(conversationId, 'event', {type:'user.question', payload:{questionId, questions}}); send(socket,reply('user.question',message.requestId,sessionId,{questionId,questions})); });
      const result = await agent.chat(sessionId!, message.payload.message, {url:String(cfg.url ?? ''),apiKey:String(cfg.apiKey ?? ''),model:String(cfg.model ?? ''),systemPrompt:String(cfg.systemPrompt ?? ''),usageRules:String(cfg.usageRules ?? ''),conversationId}, (type, payload) => { if (type !== 'llm.token') void conversationLog(conversationId, 'event', {type, payload}); send(socket, reply(type === 'llm.token' ? 'agent.token' : type, message.requestId, sessionId, payload)); }, controller.signal, message.payload.history ?? [], askUser);
      active.delete(message.requestId);
      return send(socket, reply('agent.done', message.requestId, sessionId, {content:result}));
    }
    if (message.type === 'chat.cancel') {
      active.get(message.requestId)?.abort(new Error('cancelled'));
      // reject 挂起中的提问，让卡在 await askUser 的工具 worker 走 TOOL_ERROR 退出，避免会话锁死
      for (const [questionId, entry] of answers) if (entry.requestId === message.requestId) { entry.reject(new Error('user question cancelled')); answers.delete(questionId); }
      return send(socket, reply('agent.cancelled', message.requestId, sessionId));
    }
    if (message.type === 'session.reset') agent.reset(sessionId!);
    if (message.type === 'agent.compact') return send(socket, reply('agent.done', message.requestId, sessionId, {content:agent.compact(sessionId!)}));
    if (message.type === 'session.stats') return send(socket, reply('session.stats', message.requestId, sessionId, agent.stats(sessionId!)));
    if (message.type === 'tools.list') return send(socket, reply('tools.list', message.requestId, sessionId, {tools:agent.tools()}));
    send(socket, reply('ack', message.requestId, sessionId));
  } catch (error) { active.delete(message.requestId); const value = error as {code?:string}; send(socket, {type:'agent.error', requestId:message.requestId, sessionId, error:{code:value.code ?? 'INTERNAL_ERROR', message:String(error)}}); }
}
function send(socket: WebSocket, value: unknown) { if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(value)); }
