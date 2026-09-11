import { spawn } from 'node:child_process';
import { ToolRegistry, ToolContext } from './types.js';

const MAX_OUTPUT = 64 * 1024;
function deadline(parent: AbortSignal, ms: number) { const controller=new AbortController(); const timer=setTimeout(()=>controller.abort(new Error('command timeout')),ms); const stop=()=>controller.abort(parent.reason); parent.addEventListener('abort',stop,{once:true}); controller.signal.addEventListener('abort',()=>{clearTimeout(timer);parent.removeEventListener('abort',stop)},{once:true}); return controller.signal; }

async function run(command: string, shell: string, cwd: string, timeoutMs: number, signal: AbortSignal) {
  return new Promise<string>((resolve, reject) => {
    const isPowerShell = process.platform === 'win32' && shell.toLowerCase().endsWith('powershell.exe');
    const args = isPowerShell ? ['-NoProfile','-NonInteractive','-Command',command] : ['-lc', command];
    // Windows PowerShell 默认使用系统代码页；统一切换为 UTF-8，避免中文输出写入日志后乱码。
    const child = spawn(shell, args, {cwd, windowsHide:true}); let out=''; let err=''; let timedOut=false;
    const outChunks: Buffer[] = []; const errChunks: Buffer[] = [];
    child.stdout.on('data', value=>outChunks.push(Buffer.from(value))); child.stderr.on('data', value=>errChunks.push(Buffer.from(value)));
    const timer=setTimeout(()=>{timedOut=true;child.kill();},timeoutMs); const abort=()=>child.kill();
    signal.addEventListener('abort',abort,{once:true});
    child.on('error',reject); child.on('close',(code,term)=>{clearTimeout(timer);signal.removeEventListener('abort',abort);if(signal.aborted)return reject(Object.assign(new Error('command aborted'),{code:'COMMAND_ABORTED'}));const encoding=process.platform==='win32'?'gb18030':'utf-8';const decoder=new TextDecoder(encoding);out=decoder.decode(Buffer.concat(outChunks));err=decoder.decode(Buffer.concat(errChunks));const trim=(v:string)=>v.length>MAX_OUTPUT?`${v.slice(0,MAX_OUTPUT)}\n[output truncated]`:v;resolve(JSON.stringify({exitCode:code,signal:term,timedOut,stdout:trim(out),stderr:trim(err)}));});
  });
}

export function registerShellTools(registry: ToolRegistry) {
  const properties={command:{type:'string'},description:{type:'string'},workdir:{type:'string'},timeoutMs:{type:'integer'}};
  const register=(name:'powershell'|'bash', executable:string, description:string)=>registry.register({name,description,parameters:{type:'object',properties,required:['command','description']},execute:async(args,ctx)=>{const ms=Math.min(Number(args.timeoutMs??120000),600000);const actual=name==='powershell'&&process.platform==='win32'?'powershell.exe':executable;return run(String(args.command),actual,String(args.workdir??ctx.workspacePath),ms,deadline(ctx.signal ?? new AbortController().signal,ms));}});
  register('powershell','powershell','Execute a PowerShell command in the workspace. On Windows this uses Windows PowerShell 5.1.');
  if (process.platform !== 'win32') {
    register('bash','bash','Execute a Bash command in the workspace.');
  }
  registry.register({name:'execute_command',description:'Execute a one-shot shell command in the workspace.',parameters:{type:'object',properties,required:['command','description']},execute:async(args,ctx)=>{const ms=Math.min(Number(args.timeoutMs??120000),600000);return run(String(args.command),process.platform==='win32'?'powershell.exe':'bash',String(args.workdir??ctx.workspacePath),ms,deadline(ctx.signal ?? new AbortController().signal,ms));}});
}
