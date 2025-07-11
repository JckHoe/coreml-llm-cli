import Foundation

/// Represents a parameter for a tool
public struct ToolParameter {
    public let name: String
    public let description: String
    public let type: ParameterType
    public let required: Bool
    
    public init(name: String, description: String, type: ParameterType, required: Bool = true) {
        self.name = name
        self.description = description
        self.type = type
        self.required = required
    }
    
    public enum ParameterType {
        case string
        case integer
        case boolean
        case array
        case object
    }
}

/// Represents the result of a tool execution
public struct ToolResult {
    public let success: Bool
    public let data: Any?
    public let error: String?
    
    public init(success: Bool, data: Any? = nil, error: String? = nil) {
        self.success = success
        self.data = data
        self.error = error
    }
    
    public static func success(_ data: Any? = nil) -> ToolResult {
        return ToolResult(success: true, data: data)
    }
    
    public static func failure(_ error: String) -> ToolResult {
        return ToolResult(success: false, error: error)
    }
}

/// Protocol that all tools must implement
public protocol Tool {
    var name: String { get }
    var description: String { get }
    var parameters: [ToolParameter] { get }
    
    func execute(parameters: [String: Any]) async throws -> ToolResult
}

/// Represents a tool call from the model
public struct ToolCall {
    public let name: String
    public let parameters: [String: Any]
    public let id: String
    
    public init(name: String, parameters: [String: Any], id: String = UUID().uuidString) {
        self.name = name
        self.parameters = parameters
        self.id = id
    }
}

/// Represents a tool call result for conversation context
public struct ToolCallResult {
    public let toolCall: ToolCall
    public let result: ToolResult
    public let timestamp: Date
    
    public init(toolCall: ToolCall, result: ToolResult) {
        self.toolCall = toolCall
        self.result = result
        self.timestamp = Date()
    }
}

/// Extension to convert Tool to JSON schema format
extension Tool {
    public func toJSONSchema() -> [String: Any] {
        var schema: [String: Any] = [
            "name": name,
            "description": description,
            "parameters": [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ]
        
        var properties: [String: Any] = [:]
        var required: [String] = []
        
        for parameter in parameters {
            let parameterSchema: [String: Any] = [
                "type": parameter.type.jsonString,
                "description": parameter.description
            ]
            properties[parameter.name] = parameterSchema
            
            if parameter.required {
                required.append(parameter.name)
            }
        }
        
        if var parametersDict = schema["parameters"] as? [String: Any] {
            parametersDict["properties"] = properties
            parametersDict["required"] = required
            schema["parameters"] = parametersDict
        }
        
        return schema
    }
}

extension ToolParameter.ParameterType {
    var jsonString: String {
        switch self {
        case .string: return "string"
        case .integer: return "integer"
        case .boolean: return "boolean"
        case .array: return "array"
        case .object: return "object"
        }
    }
}