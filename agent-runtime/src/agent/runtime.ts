import { ToolRegistry } from '../tools/types.js';
import { AgentSession } from './session.js';
import { executeToolCalls } from './tool-scheduler.js';
import { streamComplete, complete, LlmConfig } from '../llm/client.js';
import { toPlainText, toUserContent } from '../llm/content-adapter.js';
import { extractAttachments } from '../llm/attachment-extractor.js';
import { AGENT_SYSTEM_PROMPT } from './system-prompt.js';
import { AgentQuestion, WsAttachment } from '../protocol.js';
import { expandSkillRefs } from '../services/skill-service.js';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { stat } from 'node:fs/promises';

function defaultWorkspacePath() { return join(homedir(), 'Desktop'); }
/** 每次 runtime 启动都从桌面开始；/cd 只在当前 runtime 生命周期内生效。 */
function initialWorkspacePath() { return defaultWorkspacePath(); }

export class AgentRuntime {
  private readonly sessions = new Map<string, AgentSession>();
  constructor(private readonly registry: ToolRegistry) {}
  /** 会话工作区（工具相对路径基准与命令默认 cwd）：内存缓存 > 本次 runtime 的桌面默认，多会话互不影响 */
  private sessionWorkspace(sessionId: string): string {
    const session = this.session(sessionId);
    if (session.workspacePath == null) session.workspacePath = initialWorkspacePath();
    return session.workspacePath;
  }
  getWorkspace(sessionId: string) { return this.sessionWorkspace(sessionId); }
  /** 切换工作区（相对路径按该会话当前工作区解析）；仅在当前 runtime 生命周期内生效 */
  async setWorkspace(sessionId: string, path: string) {
    const resolved = resolve(this.sessionWorkspace(sessionId), path.trim());
    let stats; try { stats = await stat(resolved); } catch { throw new Error(`目录不存在：${resolved}（相对路径按当前工作区解析）`); }
    if (!stats.isDirectory()) throw new Error(`不是目录：${resolved}`);
    this.session(sessionId).workspacePath = resolved;
    return resolved;
  }
  session(id: string) { let value = this.sessions.get(id); if (!value) { value = new AgentSession(id); this.sessions.set(id, value); } return value; }
  async chat(sessionId: string, message: string, attachments: WsAttachment[], config: LlmConfig, onEvent: (type:string,payload:Record<string,unknown>) => void, signal: AbortSignal, history: Array<{role:string;content:unknown}> = [], askUser?: (questions:AgentQuestion[])=>Promise<string[][]>, permissionMode = 'ask') {
    const session = this.session(sessionId);
    return session.runExclusive(async () => {
      session.turn++; session.step = 0; session.append('turn/start',{message}); onEvent('turn.start',{turn:session.turn});
      // 工作区在轮开始时取本会话快照：轮内工具与提示都用同一基准，其他会话（或本会话排队期间）的 /cd 不影响进行中的一轮
      const workspacePath = this.sessionWorkspace(sessionId);
      // 历史轮只回放文本（多模态块经 toPlainText 归一化），图片仅当前轮发送；
      // user 轮的 @技能 引用同步展开——Flutter 传入的 history 是原始文本
      // （会话文件存原文），不展开则重开会话后引用轮丢技能正文
      if (session.messages.length === 0 && history.length) {
        for (const item of history) {
          const text = toPlainText(item.content);
          session.messages.push({ role: item.role, content: item.role === 'user' ? await expandSkillRefs(text) : text });
        }
      }
      session.messages.push({role:'system',content:AGENT_SYSTEM_PROMPT});
      // 工作区基准随 /cd 变化，每轮注入最新值，保证 LLM 知道相对路径的解析基准
      session.messages.push({role:'system',content:`当前工作区目录：${workspacePath}。read/write/edit/glob/grep 与命令工具的相对路径一律以该目录为基准。`});
      if (config.systemPrompt || config.usageRules || config.personality) {
      const configuredPersonality = config.systemPrompt?.match(/\[personality:(humor|serious|concise)\]/)?.[1] ?? config.personality ?? 'humor';
      const personality = configuredPersonality === 'serious' ? '严谨、专业、克制，避免玩梗。' : configuredPersonality === 'concise' ? '简洁直接，优先给出结论，避免冗余。' : '风格幽默，可以使用适量网络热词热梗；不刻意讨好，保持自己的性格。';
      const custom = [config.systemPrompt, config.usageRules ? `使用规范：\n${config.usageRules}` : '', `当前性格：${personality}`].filter(Boolean).join('\n\n');
      session.messages.push({role:'system',content:custom});
      }
      // 文本/PDF 附件先在 Node 侧提取为文本，再统一多模态组装（图片在前、文字在后）
      await extractAttachments(attachments, signal);
      // @技能 引用在本轮展开（原句保留、末尾附加技能指令块，见 skill-service.ts）；
      // UI 气泡与会话落盘仍是原始文本，仅发给 LLM 的上下文带技能正文
      const expandedMessage = await expandSkillRefs(message);
      session.messages.push({role:'user',content:toUserContent(expandedMessage, attachments)});
      for (let iteration=1; iteration<=30; iteration++) {
        signal.throwIfAborted(); session.step=iteration; session.append('step/start'); onEvent('step.start',{turn:session.turn,step:iteration});
        const response = await streamComplete(config, session.messages, this.registry.definitions().map(tool => ({type:'function',function:tool})), signal, text => onEvent('llm.token',{text}));
        session.messages.push({role:'assistant',content:response.content, ...(response.toolCalls.length ? {tool_calls:response.toolCalls.map(call=>({id:call.id,type:'function',function:{name:call.name,arguments:JSON.stringify(call.arguments)}}))} : {})});
        if (response.content) session.append('assistant/message',{content:response.content});
        if (!response.toolCalls.length) { session.append('step/end',{reason:'completed'}); onEvent('step.end',{reason:'completed'}); session.append('turn/end',{reason:'completed'}); onEvent('turn.end',{reason:'completed'}); return response.content; }
        const { WorkspacePermissionService } = await import('../services/workspace-permission.js');
        const permissions = new WorkspacePermissionService(); permissions.setMode(permissionMode);
        const results = await executeToolCalls(this.registry,response.toolCalls,{workspacePath,sessionId,requestId:'',permissionMode:'accept',askUser,permissions},signal,4,onEvent);
        for (const result of results) session.messages.push({role:'tool',content:result.error ? `Error: ${result.error.message}` : serializeToolResult(result.output),tool_call_id:result.id});
        session.append('step/end',{reason:'tool_calls'}); onEvent('step.end',{reason:'tool_calls'});
      }
      // 超步数兜底：文案必须经 onToken 流出再 return（流式契约）。勿 throw——异常会让已流出文本的会话以"请求失败"收尾，错误文本还会作为 assistant 消息落盘污染 history
      const fallback = `\n\n（已达到本轮最大步数 30 步，先在这里收尾，上述文件改动均已生效。任务未完可发「继续」接着做。）`;
      onEvent('llm.token', {text: fallback});
      session.messages.push({role:'assistant', content: fallback});
      session.append('assistant/message', {content: fallback});
      session.append('turn/end', {reason: 'max_steps'}); onEvent('turn.end', {reason: 'max_steps'});
      return fallback;
    });
  }
  reset(sessionId: string) { this.sessions.delete(sessionId); }
  async compact(sessionId: string, config: LlmConfig): Promise<string> {
    const session = this.session(sessionId);
    return session.runExclusive(async () => {
      if (!session.messages.length) return '当前会话没有可压缩的上下文。';
      const source = session.messages
        .filter(message => message.role !== 'system')
        .map(message => `${message.role}: ${toPlainText(message.content)}`)
        .join('\n');
      if (!source.trim()) return '当前会话没有可压缩的参与者对话。';
      const response = await complete(config, [{role:'system', content:'你是会话上下文压缩器。只摘要参与者对话中的事实、用户目标、已确认决定、实际文件改动和待办事项。不要摘要或改写系统下发的角色设定、行为约束、使用规范或其他系统消息；这些内容由系统提示词负责。只输出摘要。'}, {role:'user', content:source}], [], new AbortController().signal);
      const summary = response.content.trim();
      if (!summary) throw new Error('压缩器返回了空摘要');
      session.messages.splice(0, session.messages.length, {role:'system', content:`以下是此前会话的压缩摘要：\n${summary}`});
      session.append('context/compact', {messageCount: session.messages.length, summary});
      return summary;
    });
  }
  stats(sessionId: string) {
    const s = this.session(sessionId);
    const contextChars = s.messages.reduce((total, message) => total + toPlainText(message.content).length, 0);
    const totalTokens = Math.ceil(contextChars / 4);
    const maxTokens = 32000;
    const compactEvents = s.events.filter(event => event.type === 'context/compact');
    return {sessionId, messageCount:s.messages.length, eventCount:s.events.length, contextChars, totalTokens, maxTokens, usagePercent:Math.round(totalTokens / maxTokens * 100), turn:s.turn, step:s.step, lastCompactionAt:compactEvents.at(-1)?.at ?? null};
  }
  tools() { return this.registry.definitions(); }
  async executeTools(sessionId:string, requestId:string, calls:import('./tool-scheduler.js').ToolCall[], signal:AbortSignal, onEvent:(type:string,payload:Record<string,unknown>)=>void) { return executeToolCalls(this.registry,calls,{workspacePath:this.sessionWorkspace(sessionId),sessionId,requestId,permissionMode:'accept'},signal,4,onEvent); }
}

function serializeToolResult(value: unknown): string {
  if (typeof value === 'string') return value;
  try { return JSON.stringify(value); } catch { return String(value); }
}
