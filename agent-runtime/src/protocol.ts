export type ClientMessage =
  | { type: 'hello'; requestId: string; payload: { token?: string; protocolVersion?: number } }
  | { type: 'chat.start'; requestId: string; sessionId: string; payload: { message: string; history?: Array<{role:string;content:string}>; mode?: string; llm?: {url?:string;apiKey?:string;model?:string} } }
  | { type: 'chat.cancel' | 'session.reset' | 'agent.compact' | 'session.stats' | 'tools.list'; requestId: string; sessionId: string };

export interface ServerMessage { type: string; requestId?: string; sessionId?: string; payload?: Record<string, unknown>; error?: { code: string; message: string }; }

export function reply(type: string, requestId: string, sessionId: string | undefined, payload: Record<string, unknown> = {}): ServerMessage {
  return { type, requestId, ...(sessionId ? {sessionId} : {}), payload };
}
