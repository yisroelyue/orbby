export interface ToolContext { workspacePath: string; sessionId: string; requestId: string; permissionMode: string; }
export interface ToolDefinition { name: string; description: string; parameters: Record<string, unknown>; execute?: (args: Record<string, unknown>, context: ToolContext) => Promise<string>; }
export class ToolRegistry {
  private readonly tools = new Map<string, ToolDefinition>();
  register(tool: ToolDefinition) { this.tools.set(tool.name, tool); }
  definitions() { return [...this.tools.values()].map(({name, description, parameters}) => ({name, description, parameters})); }
  async execute(name: string, args: Record<string, unknown>, context: ToolContext) {
    const tool = this.tools.get(name);
    if (!tool?.execute) throw new Error(`Tool '${name}' is not implemented`);
    return tool.execute(args, context);
  }
}
