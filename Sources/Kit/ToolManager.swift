import Foundation

/// Manages available tools and their execution
public class ToolManager {
    private var tools: [String: Tool] = [:]
    
    public init() {}
    
    /// Register a tool with the manager
    public func registerTool(_ tool: Tool) {
        tools[tool.name] = tool
    }
    
    /// Register multiple tools
    public func registerTools(_ tools: [Tool]) {
        for tool in tools {
            registerTool(tool)
        }
    }
    
    /// Get all registered tools
    public func getTools() -> [Tool] {
        return Array(tools.values)
    }
    
    /// Get a specific tool by name
    public func getTool(name: String) -> Tool? {
        return tools[name]
    }
    
    /// Check if a tool is available
    public func hasToolNamed(_ name: String) -> Bool {
        return tools[name] != nil
    }
    
    /// Execute a tool call
    public func executeTool(call: ToolCall) async throws -> ToolCallResult {
        guard let tool = tools[call.name] else {
            let result = ToolResult.failure("Tool '\(call.name)' not found")
            return ToolCallResult(toolCall: call, result: result)
        }
        
        do {
            let result = try await tool.execute(parameters: call.parameters)
            return ToolCallResult(toolCall: call, result: result)
        } catch {
            let result = ToolResult.failure("Tool execution failed: \(error.localizedDescription)")
            return ToolCallResult(toolCall: call, result: result)
        }
    }
    
    /// Execute multiple tool calls
    public func executeTools(calls: [ToolCall]) async throws -> [ToolCallResult] {
        var results: [ToolCallResult] = []
        
        for call in calls {
            let result = try await executeTool(call: call)
            results.append(result)
        }
        
        return results
    }
    
    /// Get tool definitions as JSON schema format for LLM consumption
    public func getToolDefinitions() -> [[String: Any]] {
        return tools.values.map { $0.toJSONSchema() }
    }
    
    /// Get tool definitions as JSON string
    public func getToolDefinitionsJSON() -> String {
        let definitions = getToolDefinitions()
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: definitions, options: [.prettyPrinted])
            return String(data: jsonData, encoding: .utf8) ?? "[]"
        } catch {
            return "[]"
        }
    }
    
    /// Validate tool call parameters against tool schema
    public func validateToolCall(_ call: ToolCall) -> Bool {
        guard let tool = tools[call.name] else {
            return false
        }
        
        // Check required parameters
        for parameter in tool.parameters where parameter.required {
            if call.parameters[parameter.name] == nil {
                return false
            }
        }
        
        // Basic type validation could be added here
        return true
    }
    
    /// Remove a tool from the registry
    public func unregisterTool(name: String) {
        tools.removeValue(forKey: name)
    }
    
    /// Clear all tools
    public func clearTools() {
        tools.removeAll()
    }
}

/// Extension to provide default tools
extension ToolManager {
    /// Create a tool manager with default tools
    public static func withDefaultTools() -> ToolManager {
        let manager = ToolManager()
        
        // Register the anonymizer tool
        manager.registerTool(AnonymizerTool())
        
        return manager
    }
}

/// Errors that can occur during tool execution
public enum ToolError: Error, LocalizedError {
    case toolNotFound(String)
    case invalidParameters(String)
    case executionFailed(String)
    case invalidToolCall(String)
    
    public var errorDescription: String? {
        switch self {
        case .toolNotFound(let name):
            return "Tool '\(name)' not found"
        case .invalidParameters(let message):
            return "Invalid parameters: \(message)"
        case .executionFailed(let message):
            return "Tool execution failed: \(message)"
        case .invalidToolCall(let message):
            return "Invalid tool call: \(message)"
        }
    }
}