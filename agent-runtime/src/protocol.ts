export type ClientMessage =
  | { type: 'hello'; requestId: string; payload: { token?: string; protocolVersion?: number } }
  | { type: 'chat.start'; requestId: string; sessionId: string; payload: { message: string; history?: Array<{role:string;content:string}>; mode?: string; llm?: {url?:string;apiKey?:string;model?:string;systemPrompt?:string;usageRules?:string} } }
  | { type: 'chat.cancel' | 'session.reset' | 'agent.compact' | 'session.stats' | 'tools.list'; requestId: string; sessionId: string }
  | { type: 'user.answer'; requestId: string; sessionId: string; payload: { questionId: string; answers: string[][] } };

/** ask_user_question / 目录权限确认共用的结构化问题（type 省略时按 options 是否为空推断） */
export interface AgentQuestionOption { label: string; description?: string }
export interface AgentQuestion {
  question: string;
  header?: string;
  type?: 'choice' | 'text';
  options?: AgentQuestionOption[];
  multiSelect?: boolean;
}

export interface ServerMessage { type: string; requestId?: string; sessionId?: string; payload?: Record<string, unknown>; error?: { code: string; message: string }; }

export function reply(type: string, requestId: string, sessionId: string | undefined, payload: Record<string, unknown> = {}): ServerMessage {
  return { type, requestId, ...(sessionId ? {sessionId} : {}), payload };
}
