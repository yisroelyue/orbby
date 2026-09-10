import { WebSocketServer, WebSocket } from 'ws';
import { ClientMessage, reply } from './protocol.js';
import { ToolRegistry } from './tools/types.js';
import { AgentRuntime } from './agent/runtime.js';
import { registerFilesystemTools } from './tools/fs-tools.js';

export function startServer(port = Number(process.env.ORBBY_AGENT_PORT ?? 43127)) {
  const registry = new ToolRegistry();
  registerFilesystemTools(registry);
  const agent = new AgentRuntime(registry);
  const active = new Map<string, AbortController>();
  const wss = new WebSocketServer({host: '127.0.0.1', port});
  wss.on('connection', socket => socket.on('message', raw => void handle(socket, agent, active, JSON.parse(raw.toString()) as ClientMessage)));
  wss.on('listening', () => console.log(JSON.stringify({status:'ready', port, protocolVersion:1})));
  return wss;
}

async function handle(socket: WebSocket, agent: AgentRuntime, active: Map<string, AbortController>, message: ClientMessage) {
  const sessionId = 'sessionId' in message ? message.sessionId : undefined;
  try {
    if (message.type === 'hello') return send(socket, reply('hello.ok', message.requestId, undefined, {protocolVersion:1}));
    if (message.type === 'chat.start') {
      const controller = new AbortController(); active.set(message.requestId, controller);
      const cfg = (message.payload as any).llm ?? {};
      const result = await agent.chat(sessionId!, message.payload.message, {url:String(cfg.url ?? ''),apiKey:String(cfg.apiKey ?? ''),model:String(cfg.model ?? '')}, (type, payload) => send(socket, reply(type === 'llm.token' ? 'agent.token' : type, message.requestId, sessionId, payload)), controller.signal, message.payload.history ?? []);
      active.delete(message.requestId);
      return send(socket, reply('agent.done', message.requestId, sessionId, {content:result}));
    }
    if (message.type === 'chat.cancel') { active.get(message.requestId)?.abort(new Error('cancelled')); return send(socket, reply('agent.cancelled', message.requestId, sessionId)); }
    if (message.type === 'session.reset') agent.reset();
    if (message.type === 'agent.compact') return send(socket, reply('agent.done', message.requestId, sessionId, {content:agent.compact()}));
    if (message.type === 'session.stats') return send(socket, reply('session.stats', message.requestId, sessionId, agent.stats()));
    if (message.type === 'tools.list') return send(socket, reply('tools.list', message.requestId, sessionId, {tools:agent.tools()}));
    send(socket, reply('ack', message.requestId, sessionId));
  } catch (error) { active.delete(message.requestId); const value = error as {code?:string}; send(socket, {type:'agent.error', requestId:message.requestId, sessionId, error:{code:value.code ?? 'INTERNAL_ERROR', message:String(error)}}); }
}
function send(socket: WebSocket, value: unknown) { if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(value)); }
