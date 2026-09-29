import { randomUUID } from 'node:crypto';
export class AgentSession {
    id;
    events = [];
    turn = 0;
    step = 0;
    messages = [];
    /** 本会话工作区（工具相对路径基准）；null = 未初始化，由 runtime 惰性填充（本次启动默认桌面） */
    workspacePath = null;
    active;
    constructor(id = `session-${randomUUID()}`) { this.id = id; }
    append(type, payload) { this.events.push({ type, turn: this.turn, ...(this.step ? { step: this.step } : {}), at: Date.now(), ...(payload ? { payload } : {}) }); }
    async runExclusive(job) {
        while (this.active)
            await this.active.catch(() => undefined);
        let resolve;
        const done = new Promise(r => { resolve = r; });
        this.active = done;
        try {
            return await job();
        }
        finally {
            this.active = undefined;
            resolve();
        }
    }
}
