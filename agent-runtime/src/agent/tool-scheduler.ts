import { ToolRegistry, ToolContext } from '../tools/types.js';

export interface ToolCall { id: string; name: string; arguments: Record<string, unknown>; }
export async function executeToolCalls(registry: ToolRegistry, calls: ToolCall[], context: ToolContext, signal: AbortSignal, maxParallel = 4, onEvent?: (type:string, payload:Record<string,unknown>) => void) {
  context.signal = signal;
  const results: Array<{id:string; name:string; output:unknown; changes?:unknown[]; error?:{code:string;message:string}}> = [];
  let cursor = 0;
  const worker = async () => { while (cursor < calls.length) { const index = cursor++; const call = calls[index]; if (signal.aborted) { results[index] = {id:call.id,name:call.name,output:'',error:{code:'ABORTED_BEFORE_DISPATCH',message:'Tool call aborted before dispatch'}}; continue; } onEvent?.('tool.start',{id:call.id,name:call.name,arguments:call.arguments}); try { const result = await registry.execute(call.name, call.arguments, context); const value = result && typeof result === 'object' && 'output' in result ? result as {output: unknown; changes?: unknown[]} : {output: result}; results[index] = {id:call.id,name:call.name,output:value.output,changes:value.changes}; onEvent?.('tool.result',{id:call.id,name:call.name,output:value.output,changes:value.changes ?? []}); } catch (error) { const message = String(error); results[index] = {id:call.id,name:call.name,output:'',error:{code:'TOOL_ERROR',message}}; onEvent?.('tool.error',{id:call.id,name:call.name,message}); } } };
  await Promise.all(Array.from({length:Math.min(maxParallel, calls.length)}, () => worker()));
  return results;
}
