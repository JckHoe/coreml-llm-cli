import Foundation

/// Formats prompts using Llama chat templates
struct ChatTemplateFormatter {
    
    /// Formats system and user prompts using Llama's chat template format
    /// - Parameters:
    ///   - systemPrompt: Optional system prompt. If nil, uses default system prompt
    ///   - userPrompt: The user's question or input
    /// - Returns: Formatted prompt string ready for tokenization
    static func formatLlamaPrompt(systemPrompt: String?, userPrompt: String) -> String {
        let effectiveSystemPrompt = systemPrompt ?? defaultSystemPrompt()
        
        return """
        <|begin_of_text|><|start_header_id|>system<|end_header_id|>

        \(effectiveSystemPrompt)<|eot_id|><|start_header_id|>user<|end_header_id|>

        \(userPrompt)<|eot_id|><|start_header_id|>assistant<|end_header_id|>

        """
    }
    
    /// Formats system and user prompts with tool definitions using Llama's chat template format
    /// - Parameters:
    ///   - systemPrompt: Optional system prompt. If nil, uses default system prompt
    ///   - userPrompt: The user's question or input
    ///   - toolManager: Tool manager containing available tools
    /// - Returns: Formatted prompt string ready for tokenization
    static func formatLlamaPromptWithTools(systemPrompt: String?, userPrompt: String, toolManager: ToolManager) -> String {
        let effectiveSystemPrompt = systemPrompt ?? defaultSystemPrompt()
        let toolDefinitions = toolManager.getToolDefinitionsJSON()
        
        let systemPromptWithTools = """
        \(effectiveSystemPrompt)

        You must ALWAYS call the anonymize_text tool. Find exactly ONE name in the user input and create a replacement name.

        ALWAYS respond with this JSON format:
        {"tool_call": {"name": "anonymize_text", "parameters": {"originalText": "found_name", "replacementText": "replacement_name"}}}

        Available tools:
        \(toolDefinitions)

        Instructions:
        1. Find exactly ONE name in the user input (the main name mentioned)
        2. Create a different replacement name
        3. Use only "originalText" and "replacementText" parameters
        4. If no names found, use empty string: {"tool_call": {"name": "anonymize_text", "parameters": {"originalText": "", "replacementText": ""}}}

        Examples:
        User: "Hello, I am Michael"
        Response: {"tool_call": {"name": "anonymize_text", "parameters": {"originalText": "Michael", "replacementText": "David"}}}

        User: "My name is Sarah"
        Response: {"tool_call": {"name": "anonymize_text", "parameters": {"originalText": "Sarah", "replacementText": "Emma"}}}
        """
        
        return """
        <|begin_of_text|><|start_header_id|>system<|end_header_id|>

        \(systemPromptWithTools)<|eot_id|><|start_header_id|>user<|end_header_id|>

        \(userPrompt)<|eot_id|><|start_header_id|>assistant<|end_header_id|>

        """
    }
    
    /// Default system prompt for when none is provided
    private static func defaultSystemPrompt() -> String {
        return "You are a helpful, honest, and harmless AI assistant."
    }
    
    /// Formats a single text input as a user prompt with default system prompt
    /// - Parameter text: The input text to format
    /// - Returns: Formatted prompt string ready for tokenization
    static func formatSingleInput(_ text: String) -> String {
        return formatLlamaPrompt(systemPrompt: nil, userPrompt: text)
    }
}