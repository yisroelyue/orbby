import { ToolRegistry, ToolContext } from '../tools/types.js';

export interface ToolCall { id: string; name: string; arguments: Record<string, unknown>; }
export async function executeToolCalls(registry: ToolRegistry, calls: ToolCall[], context: ToolContext, signal: AbortSignal, maxParallel = 4, onEvent?: (type:string, payload:Record<string,unknown>) => void) {
  const results: Array<{id:string; name:string; output:string; error?:{code:string;message:string}}> = [];
  let cursor = 0;
  const worker = async () => { while (cursor < calls.length) { const index = cursor++; const call = calls[index]; if (signal.aborted) { results[index] = {id:call.id,name:call.name,output:'',error:{code:'ABORTED_BEFORE_DISPATCH',message:'Tool call aborted before dispatch'}}; continue; } onEvent?.('tool.start',{id:call.id,name:call.name}); try { const output = await registry.execute(call.name, call.arguments, context); results[index] = {id:call.id,name:call.name,output}; onEvent?.('tool.result',{id:call.id,name:call.name,output}); } catch (error) { const message = String(error); results[index] = {id:call.id,name:call.name,output:'',error:{code:'TOOL_ERROR',message}}; onEvent?.('tool.error',{id:call.id,name:call.name,message}); } } };
  await Promise.all(Array.from({length:Math.min(maxParallel, calls.length)}, () => worker()));
  return results;
}
