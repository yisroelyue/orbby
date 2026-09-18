import { randomUUID } from 'node:crypto';
import { ContentPart } from '../llm/content-adapter.js';

export type SessionEvent = { type: string; turn: number; step?: number; at: number; payload?: Record<string, unknown> };
export class AgentSession {
  readonly id: string;
  readonly events: SessionEvent[] = [];
  turn = 0;
  step = 0;
  readonly messages: Array<{role:string;content:string|null|ContentPart[];tool_call_id?:string;tool_calls?:unknown[]}> = [];
  /** 本会话工作区（工具相对路径基准）；null = 未初始化，由 runtime 惰性填充（会话持久化值 > 全局默认） */
  workspacePath: string | null = null;
  private active: Promise<unknown> | undefined;
  constructor(id = `session-${randomUUID()}`) { this.id = id; }
  append(type: string, payload?: Record<string, unknown>) { this.events.push({type, turn:this.turn, ...(this.step ? {step:this.step} : {}), at:Date.now(), ...(payload ? {payload} : {})}); }
  async runExclusive<T>(job: () => Promise<T>): Promise<T> {
    while (this.active) await this.active.catch(() => undefined);
    let resolve!: () => void; const done = new Promise<void>(r => { resolve = r }); this.active = done;
    try { return await job(); } finally { this.active = undefined; resolve(); }
  }
}
