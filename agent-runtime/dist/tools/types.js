export class ToolRegistry {
    tools = new Map();
    register(tool) { this.tools.set(tool.name, tool); }
    definitions() { return [...this.tools.values()].map(({ name, description, parameters }) => ({ name, description, parameters })); }
    async execute(name, args, context) {
        const tool = this.tools.get(name);
        if (!tool?.execute)
            throw new Error(`Tool '${name}' is not implemented`);
        return tool.execute(args, context);
    }
}
