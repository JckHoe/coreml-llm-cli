import Foundation

/// Parses tool calls from LLM responses
public class ToolCallParser {
    
    public init() {}
    
    /// Parse tool calls from a text response
    public func parseToolCalls(from response: String) -> [ToolCall] {
        var toolCalls: [ToolCall] = []
        
        // Look for JSON-formatted tool calls in the response
        let patterns = [
            #"\{"tool_call"\s*:\s*\{[^}]*\}\s*\}"#,  // {"tool_call": {...}}
            #"\{"name"\s*:\s*"[^"]*"\s*,\s*"parameters"\s*:\s*\{[^}]*\}\s*\}"#  // {"name": "...", "parameters": {...}}
        ]
        
        for pattern in patterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
            let matches = regex?.matches(in: response, options: [], range: NSRange(location: 0, length: response.count)) ?? []
            
            for match in matches {
                let matchRange = match.range
                if let range = Range(matchRange, in: response) {
                    let matchString = String(response[range])
                    if let toolCall = parseToolCallFromJSON(matchString) {
                        toolCalls.append(toolCall)
                    }
                }
            }
        }
        
        // If no structured tool calls found, try to extract from any JSON-like structure
        if toolCalls.isEmpty {
            toolCalls.append(contentsOf: extractToolCallsFromAnyJSON(response))
        }
        
        return toolCalls
    }
    
    /// Parse a single tool call from JSON string
    private func parseToolCallFromJSON(_ jsonString: String) -> ToolCall? {
        guard let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                return parseToolCallFromDictionary(json)
            }
        } catch {
            // Try to extract tool call from nested structure
            return parseToolCallFromText(jsonString)
        }
        
        return nil
    }
    
    /// Parse tool call from dictionary
    private func parseToolCallFromDictionary(_ dict: [String: Any]) -> ToolCall? {
        // Format 1: {"tool_call": {"name": "...", "parameters": {...}}}
        if let toolCallDict = dict["tool_call"] as? [String: Any],
           let name = toolCallDict["name"] as? String,
           let parameters = toolCallDict["parameters"] as? [String: Any] {
            return ToolCall(name: name, parameters: parameters)
        }
        
        // Format 2: {"name": "...", "parameters": {...}}
        if let name = dict["name"] as? String,
           let parameters = dict["parameters"] as? [String: Any] {
            return ToolCall(name: name, parameters: parameters)
        }
        
        // Format 3: {"function": {"name": "...", "parameters": {...}}}
        if let functionDict = dict["function"] as? [String: Any],
           let name = functionDict["name"] as? String,
           let parameters = functionDict["parameters"] as? [String: Any] {
            return ToolCall(name: name, parameters: parameters)
        }
        
        return nil
    }
    
    /// Parse tool call from text using regex
    private func parseToolCallFromText(_ text: String) -> ToolCall? {
        // Try to extract name and parameters using regex
        let namePattern = #""name"\s*:\s*"([^"]*)"#
        let nameRegex = try? NSRegularExpression(pattern: namePattern, options: [])
        
        if let nameMatch = nameRegex?.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.count)),
           let nameRange = Range(nameMatch.range(at: 1), in: text) {
            let name = String(text[nameRange])
            
            // Try to extract parameters
            let parametersPattern = #""parameters"\s*:\s*(\{[^}]*\})"#
            let parametersRegex = try? NSRegularExpression(pattern: parametersPattern, options: [])
            
            if let parametersMatch = parametersRegex?.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.count)),
               let parametersRange = Range(parametersMatch.range(at: 1), in: text) {
                let parametersString = String(text[parametersRange])
                
                if let parametersData = parametersString.data(using: .utf8),
                   let parameters = try? JSONSerialization.jsonObject(with: parametersData) as? [String: Any] {
                    return ToolCall(name: name, parameters: parameters)
                }
            }
            
            // If no parameters found, create with empty parameters
            return ToolCall(name: name, parameters: [:])
        }
        
        return nil
    }
    
    /// Extract tool calls from any JSON structure in the response
    private func extractToolCallsFromAnyJSON(_ response: String) -> [ToolCall] {
        var toolCalls: [ToolCall] = []
        
        // Look for any JSON object that might contain tool information
        let jsonPattern = #"\{[^{}]*\}"#
        let regex = try? NSRegularExpression(pattern: jsonPattern, options: [.caseInsensitive])
        let matches = regex?.matches(in: response, options: [], range: NSRange(location: 0, length: response.count)) ?? []
        
        for match in matches {
            let matchRange = match.range
            if let range = Range(matchRange, in: response) {
                let jsonString = String(response[range])
                
                // Try to parse as JSON and look for tool-related keys
                if let jsonData = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    
                    // Check if this looks like a tool call attempt
                    if json.keys.contains(where: { $0.lowercased().contains("tool") || $0.lowercased().contains("name") }) {
                        if let toolCall = parseToolCallFromDictionary(json) {
                            toolCalls.append(toolCall)
                        }
                    }
                }
            }
        }
        
        return toolCalls
    }
    
    /// Check if a response contains tool calls
    public func containsToolCalls(_ response: String) -> Bool {
        let patterns = [
            #"\{"tool_call"\s*:"#,
            #"\{"name"\s*:\s*"[^"]*"\s*,\s*"parameters"\s*:"#,
            #"\{"function"\s*:"#
        ]
        
        for pattern in patterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            if let match = regex?.firstMatch(in: response, options: [], range: NSRange(location: 0, length: response.count)) {
                return true
            }
        }
        
        return false
    }
    
    /// Extract the text content from a response, removing tool calls
    public func extractTextContent(from response: String) -> String {
        var cleanedResponse = response
        
        // Remove tool call JSON blocks
        let patterns = [
            #"\{"tool_call"\s*:\s*\{[^}]*\}"#,
            #"\{"name"\s*:\s*"[^"]*"\s*,\s*"parameters"\s*:\s*\{[^}]*\}"#
        ]
        
        for pattern in patterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            cleanedResponse = regex?.stringByReplacingMatches(in: cleanedResponse, options: [], range: NSRange(location: 0, length: cleanedResponse.count), withTemplate: "") ?? cleanedResponse
        }
        
        return cleanedResponse.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Format tool call results for model consumption
    public func formatToolResults(_ results: [ToolCallResult]) -> String {
        var formatted: [String] = []
        
        for result in results {
            let toolName = result.toolCall.name
            let success = result.result.success
            
            if success {
                if let data = result.result.data {
                    // Try to serialize data as JSON
                    if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted]),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        formatted.append("Tool '\(toolName)' result: \(jsonString)")
                    } else {
                        formatted.append("Tool '\(toolName)' result: \(data)")
                    }
                } else {
                    formatted.append("Tool '\(toolName)' executed successfully")
                }
            } else {
                let error = result.result.error ?? "Unknown error"
                formatted.append("Tool '\(toolName)' failed: \(error)")
            }
        }
        
        return formatted.joined(separator: "\n")
    }
}