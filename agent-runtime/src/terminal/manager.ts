import { spawn, ChildProcessWithoutNullStreams } from 'node:child_process';
import { randomUUID } from 'node:crypto';

export interface TerminalInfo { sessionId:string; type:string; cwd:string; pid?:number; status:'running'|'exited'; }
interface Terminal { info:TerminalInfo; child:ChildProcessWithoutNullStreams; output:string; }
export class TerminalManager {
  private readonly sessions = new Map<string,Terminal>();
  open(type:string,cwd:string) { const shell=process.platform==='win32'?'powershell.exe':'bash'; const args=process.platform==='win32'?['-NoLogo','-NoProfile','-Command','-']:['-i']; const child=spawn(shell,args,{cwd,windowsHide:true}); const id=`term-${randomUUID()}`; const terminal:Terminal={info:{sessionId:id,type,cwd,pid:child.pid,status:'running'},child,output:''}; child.stdout.on('data',b=>terminal.output+=b.toString());child.stderr.on('data',b=>terminal.output+=b.toString());child.on('error',error=>{terminal.output+=`\n[terminal error] ${error.message}\n`;terminal.info.status='exited';});child.on('close',()=>terminal.info.status='exited');this.sessions.set(id,terminal);return terminal.info; }
  get(id:string){const terminal=this.sessions.get(id);if(!terminal)throw new Error(`Terminal session not found: ${id}`);return terminal;}
  async send(id:string,text:string,submit=true,signal?:AbortSignal){const t=this.get(id);if(t.info.status==='exited')throw new Error('Terminal session has exited');if(signal?.aborted)throw new Error('terminal send aborted');t.child.stdin.write(text+(submit?'\n':''));await new Promise(r=>setTimeout(r,100));return {sessionStatus:t.info,output:this.read(id)};}
  read(id:string){const t=this.get(id);const value=t.output;t.output='';return {text:value,totalLines:value?value.split(/\r?\n/).length:0};}
  close(id:string){const t=this.get(id);if(t.info.status==='running')t.child.kill();this.sessions.delete(id);return {sessionId:id,outcome:'closed'};}
  list(){return [...this.sessions.values()].map(t=>t.info);}
}
