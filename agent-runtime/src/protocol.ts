export type ClientMessage =
  | { type: 'hello'; requestId: string; payload: { token?: string; protocolVersion?: number } }
  | { type: 'chat.start'; requestId: string; sessionId: string; payload: { message: string; history?: Array<{role:string;content:unknown}>; attachments?: unknown; mode?: string; llm?: {url?:string;apiKey?:string;model?:string;platform?:string;systemPrompt?:string;usageRules?:string} } }
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

/** chat.start 附件（Flutter 侧 ChatAttachment.sendPayload），Base64 图片数据 */
export interface WsAttachment {
  id: string; fileName: string; mimeType: string; data: string; width?: number; height?: number;
  /** 文本/PDF 附件经 Node 侧预提取的文本（图片无此字段）；由 attachment-extractor 填充 */
  extractedText?: string;
  /** 提取概况（页数/是否截断），用于组装附件说明 */
  extractedInfo?: string;
}

export interface ServerMessage { type: string; requestId?: string; sessionId?: string; payload?: Record<string, unknown>; error?: { code: string; message: string }; }

export function reply(type: string, requestId: string, sessionId: string | undefined, payload: Record<string, unknown> = {}): ServerMessage {
  return { type, requestId, ...(sessionId ? {sessionId} : {}), payload };
}
