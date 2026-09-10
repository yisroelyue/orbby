import { ToolRegistry } from '../tools/types.js';
import { AgentSession } from './session.js';
import { executeToolCalls } from './tool-scheduler.js';
import { streamComplete, LlmConfig } from '../llm/client.js';

export class AgentRuntime {
  private readonly sessions = new Map<string, AgentSession>();
  constructor(private readonly registry: ToolRegistry) {}
  session(id: string) { let value = this.sessions.get(id); if (!value) { value = new AgentSession(id); this.sessions.set(id, value); } return value; }
  async chat(sessionId: string, message: string, config: LlmConfig, onEvent: (type:string,payload:Record<string,unknown>) => void, signal: AbortSignal, history: Array<{role:string;content:string}> = []) {
    const session = this.session(sessionId);
    return session.runExclusive(async () => {
      session.turn++; session.step = 0; session.append('turn/start',{message}); onEvent('turn.start',{turn:session.turn});
      if (session.messages.length === 0 && history.length) session.messages.push(...history.map(item => ({role:item.role,content:item.content})));
      session.messages.push({role:'user',content:message});
      for (let iteration=1; iteration<=30; iteration++) {
        signal.throwIfAborted(); session.step=iteration; session.append('step/start'); onEvent('step.start',{turn:session.turn,step:iteration});
        const response = await streamComplete(config, session.messages, this.registry.definitions().map(tool => ({type:'function',function:tool})), signal, text => onEvent('llm.token',{text}));
        session.messages.push({role:'assistant',content:response.content, ...(response.toolCalls.length ? {tool_calls:response.toolCalls.map(call=>({id:call.id,type:'function',function:{name:call.name,arguments:JSON.stringify(call.arguments)}}))} : {})});
        if (response.content) session.append('assistant/message',{content:response.content});
        if (!response.toolCalls.length) { session.append('step/end',{reason:'completed'}); onEvent('step.end',{reason:'completed'}); session.append('turn/end',{reason:'completed'}); onEvent('turn.end',{reason:'completed'}); return response.content; }
        const results = await executeToolCalls(this.registry,response.toolCalls,{workspacePath:process.env.ORBBY_WORKSPACE ?? process.cwd(),sessionId,requestId:'',permissionMode:'accept'},signal,4,onEvent);
        for (const result of results) session.messages.push({role:'tool',content:result.error ? `Error: ${result.error.message}` : result.output,tool_call_id:result.id});
        session.append('step/end',{reason:'tool_calls'}); onEvent('step.end',{reason:'tool_calls'});
      }
      throw new Error('Agent exceeded maximum iterations');
    });
  }
  reset(sessionId: string) { this.sessions.delete(sessionId); }
  compact(sessionId: string) { return `会话 ${sessionId} 当前有 ${this.session(sessionId).events.length} 条事件，压缩器尚未接入`; }
  stats(sessionId: string) { const s=this.session(sessionId); return {messagesCount:s.events.length,totalTokens:0,maxTokens:32000,usagePercent:0,turn:s.turn,step:s.step}; }
  tools() { return this.registry.definitions(); }
  async executeTools(sessionId:string, requestId:string, calls:import('./tool-scheduler.js').ToolCall[], signal:AbortSignal, onEvent:(type:string,payload:Record<string,unknown>)=>void) { return executeToolCalls(this.registry,calls,{workspacePath:process.env.ORBBY_WORKSPACE ?? process.cwd(),sessionId,requestId,permissionMode:'accept'},signal,4,onEvent); }
}
