import { promises as fs } from 'node:fs';
import { join } from 'node:path';
import { ToolRegistry } from './types.js';

async function findSkill(name:string, roots:string[]):Promise<{provider:string;path:string}|undefined>{for(const root of roots){const path=join(root,name,'SKILL.md');try{await fs.access(path);return {provider:root,path}}catch{}}}
export function registerSkillTools(registry:ToolRegistry){registry.register({name:'skill',description:'Load the full instructions for an available local skill.',parameters:{type:'object',properties:{name:{type:'string'}},required:['name']},execute:async(args)=>{const name=String(args.name);if(!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(name))throw new Error(`invalid skill name "${name}"`);const roots=(process.env.ORBBY_SKILLS_DIR??'').split(';').filter(Boolean);roots.push(join(process.cwd(),'.agents','skills'));const found=await findSkill(name,roots);if(!found)throw new Error(`skill "${name}" is unknown or unavailable`);return JSON.stringify({name,provider:found.provider,resourceBase:{kind:'directory',path:join(found.provider,name)},content:await fs.readFile(found.path,'utf8')});}});}
