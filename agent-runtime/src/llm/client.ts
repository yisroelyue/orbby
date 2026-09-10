export interface LlmMessage { role: string; content: string | null; tool_call_id?: string; tool_calls?: unknown[] }
export interface LlmToolCall { id: string; name: string; arguments: Record<string, unknown> }
export interface LlmResponse { content: string; toolCalls: LlmToolCall[] }
export interface LlmConfig { url: string; apiKey: string; model: string }

export async function streamComplete(config: LlmConfig, messages: LlmMessage[], tools: unknown[], signal: AbortSignal, onText: (text:string)=>void): Promise<LlmResponse> {
  if (!config.url || !config.apiKey || !config.model) throw new Error('LLM configuration is incomplete');
  const response = await fetch(config.url, {method:'POST',signal,headers:{'content-type':'application/json',authorization:`Bearer ${config.apiKey}`},body:JSON.stringify({model:config.model,messages,tools:tools.length?tools:undefined,stream:true})});
  if (!response.ok || !response.body) throw Object.assign(new Error(`LLM request failed: ${response.status} ${await response.text()}`),{code:'LLM_REQUEST_ERROR'});
  const calls = new Map<number,{id:string;name:string;args:string}>(); let content=''; let buffer='';
  for await (const chunk of response.body as any) { buffer += Buffer.from(chunk).toString('utf8'); const lines=buffer.split(/\r?\n/); buffer=lines.pop() ?? ''; for(const line of lines){if(!line.startsWith('data:'))continue; const raw=line.slice(5).trim(); if(raw==='[DONE]')continue; const delta=(JSON.parse(raw) as any).choices?.[0]?.delta; if(delta?.content){content+=delta.content;onText(delta.content)} for(const item of delta?.tool_calls ?? []){const index=Number(item.index ?? 0);const call=calls.get(index) ?? {id:String(item.id ?? `call-${index}`),name:'',args:''};if(item.id)call.id=String(item.id);if(item.function?.name)call.name+=item.function.name;if(item.function?.arguments)call.args+=item.function.arguments;calls.set(index,call)}}}
  return {content,toolCalls:[...calls.values()].map(call=>({id:call.id,name:call.name,arguments:JSON.parse(call.args||'{}')}))};
}

export async function complete(config: LlmConfig, messages: LlmMessage[], tools: unknown[], signal: AbortSignal): Promise<LlmResponse> {
  if (!config.url || !config.apiKey || !config.model) throw new Error('LLM configuration is incomplete');
  const response = await fetch(config.url, {method:'POST', signal, headers:{'content-type':'application/json',authorization:`Bearer ${config.apiKey}`}, body:JSON.stringify({model:config.model,messages,tools:tools.length?tools:undefined,stream:false})}).catch(error => { throw Object.assign(new Error(`LLM connection failed: ${String(error)}`), {code:'LLM_CONNECTION_ERROR'}); });
  if (!response.ok) throw Object.assign(new Error(`LLM request failed: ${response.status} ${await response.text()}`), {code:'LLM_REQUEST_ERROR', status:response.status});
  const body = await response.json() as any; const message = body.choices?.[0]?.message;
  if (!message) throw new Error('LLM response did not contain a message');
  const toolCalls: LlmToolCall[] = (message.tool_calls ?? []).map((call:any) => ({id:String(call.id),name:String(call.function.name),arguments:JSON.parse(call.function.arguments || '{}')}));
  return {content:message.content ?? '', toolCalls};
}
