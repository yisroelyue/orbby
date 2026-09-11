import { TerminalManager } from '../terminal/manager.js';
import { ToolRegistry } from './types.js';

export function registerTerminalTools(registry:ToolRegistry, manager=new TerminalManager()) {
  registry.register({name:'terminal_open',description:'Open a persistent shell terminal session.',parameters:{type:'object',properties:{type:{type:'string'},cwd:{type:'string'}},required:[]},execute:async(args,ctx)=>manager.open(String(args.type??'shell'),String(args.cwd??ctx.workspacePath))});
  registry.register({name:'terminal_send',description:'Send input to a persistent terminal session.',parameters:{type:'object',properties:{sessionId:{type:'string'},text:{type:'string'},submit:{type:'boolean'}},required:['sessionId','text']},execute:async(args,ctx)=>manager.send(String(args.sessionId),String(args.text),args.submit!==false,ctx.signal)});
  registry.register({name:'terminal_read',description:'Read buffered output from a persistent terminal session.',parameters:{type:'object',properties:{sessionId:{type:'string'}},required:['sessionId']},execute:async(args)=>manager.read(String(args.sessionId))});
  registry.register({name:'terminal_close',description:'Close a persistent terminal session.',parameters:{type:'object',properties:{sessionId:{type:'string'}},required:['sessionId']},execute:async(args)=>manager.close(String(args.sessionId))});
  registry.register({name:'terminal_list',description:'List persistent terminal sessions.',parameters:{type:'object',properties:{},required:[]},execute:async()=>manager.list()});
}
