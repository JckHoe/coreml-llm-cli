import Foundation
import Tokenizers

enum OutputFormat {
    case standard
    case json
}

/// TextGenerator uses an LLM `ModelPipeline` to generate text.
class TextGenerator {
    let pipeline: ModelPipeline
    let tokenizer: Tokenizer
    private let toolManager: ToolManager?
    private let toolCallParser: ToolCallParser
    private let enableToolCalling: Bool

    init(pipeline: ModelPipeline, tokenizer: Tokenizer, toolManager: ToolManager? = nil) {
        self.pipeline = pipeline
        self.tokenizer = tokenizer
        self.toolManager = toolManager
        self.toolCallParser = ToolCallParser()
        self.enableToolCalling = toolManager != nil
    }

    func generate(text: String, maxNewTokens: Int, outputFormat: OutputFormat = .standard) async throws {

        let loadTimer = CodeTimer()
        try pipeline.load()
        let loadDuration = loadTimer.elapsed()

        let tokens = tokenizer.encode(text: text)

        var predictions = [Prediction]()
        
        if outputFormat == .standard {
            tokens.forEach { print($0, terminator: " ") }
            fflush(stdout)
        }

        let eosTokens = getEosTokens(from: tokenizer)
        
        if outputFormat == .standard {
            print("EOS tokens found: \(eosTokens)")
        }
        
        for try await prediction in try pipeline.predict(tokens: tokens, maxNewTokens: maxNewTokens, eosTokenIds: eosTokens) {
            predictions.append(prediction)
            if outputFormat == .standard {
                print(prediction.newToken, terminator: " ")
                fflush(stdout)
            }
        }
        
        let allTokens = predictions.last?.allTokens ?? tokens
        let newTokens = Array(allTokens.suffix(from: tokens.count))
        
        let filteredNewTokens = removeStopTokens(from: newTokens, eosTokens: eosTokens)
        let generatedText = tokenizer.decode(tokens: filteredNewTokens)
        let fullText = tokenizer.decode(tokens: allTokens)
        
        // Check for tool calls if tool calling is enabled
        if enableToolCalling {
            let toolCallResults = try await processToolCalls(in: generatedText)
            
            if !toolCallResults.isEmpty {
                // Output tool call results
                if outputFormat == .json {
                    outputJSONWithToolCalls(
                        inputText: text,
                        generatedText: generatedText,
                        toolCallResults: toolCallResults,
                        loadDuration: loadDuration,
                        predictions: predictions
                    )
                } else {
                    outputStandardWithToolCalls(
                        generatedText: fullText,
                        toolCallResults: toolCallResults,
                        loadDuration: loadDuration,
                        predictions: predictions
                    )
                }
                return
            }
        }
        
        if outputFormat == .json {
            outputJSON(
                inputText: text,
                generatedText: generatedText,
                loadDuration: loadDuration,
                predictions: predictions
            )
        } else {
            outputStandard(
                generatedText: fullText,
                loadDuration: loadDuration,
                predictions: predictions
            )
        }
    }
    
    func generateInteractive(text: String, maxNewTokens: Int, outputFormat: OutputFormat = .standard) async throws {
        let tokens = tokenizer.encode(text: text)
        var predictions = [Prediction]()
        
        let eosTokens = getEosTokens(from: tokenizer)
        
        for try await prediction in try pipeline.predict(tokens: tokens, maxNewTokens: maxNewTokens, eosTokenIds: eosTokens) {
            predictions.append(prediction)
        }
        
        let allTokens = predictions.last?.allTokens ?? tokens
        let newTokens = Array(allTokens.suffix(from: tokens.count))
        
        let filteredNewTokens = removeStopTokens(from: newTokens, eosTokens: eosTokens)
        let generatedText = tokenizer.decode(tokens: filteredNewTokens)
        
        // Check for tool calls if tool calling is enabled
        if enableToolCalling {
            let toolCallResults = try await processToolCalls(in: generatedText)
            
            if !toolCallResults.isEmpty {
                if outputFormat == .json {
                    outputInteractiveJSONWithToolCalls(generatedText: generatedText, toolCallResults: toolCallResults, predictions: predictions)
                } else {
                    let textContent = toolCallParser.extractTextContent(from: generatedText)
                    if !textContent.isEmpty {
                        print(textContent)
                    }
                    
                    // Display tool call results
                    for result in toolCallResults {
                        print("\n[Tool: \(result.toolCall.name)]")
                        if result.result.success {
                            if let data = result.result.data,
                               let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted]),
                               let jsonString = String(data: jsonData, encoding: .utf8) {
                                print(jsonString)
                            }
                        } else {
                            print("Error: \(result.result.error ?? "Unknown error")")
                        }
                    }
                }
                fflush(stdout)
                return
            }
        }
        
        if outputFormat == .json {
            outputInteractiveJSON(generatedText: generatedText, predictions: predictions)
        } else {
            print(generatedText)
        }
        
        fflush(stdout)
    }
    
    // MARK: - Tool Calling Support
    
    private func processToolCalls(in text: String) async throws -> [ToolCallResult] {
        guard let toolManager = toolManager else {
            return []
        }
        
        let toolCalls = toolCallParser.parseToolCalls(from: text)
        
        if toolCalls.isEmpty {
            return []
        }
        
        var results: [ToolCallResult] = []
        
        for toolCall in toolCalls {
            let result = try await toolManager.executeTool(call: toolCall)
            results.append(result)
        }
        
        return results
    }
    
    private func outputStandardWithToolCalls(generatedText: String, toolCallResults: [ToolCallResult], loadDuration: Measurement<UnitDuration>, predictions: [Prediction]) {
        print("\n")
        
        // Extract and display text content
        let textContent = toolCallParser.extractTextContent(from: generatedText)
        if !textContent.isEmpty {
            print(textContent)
        }
        
        // Display tool call results
        for result in toolCallResults {
            print("\n[Tool: \(result.toolCall.name)]")
            if result.result.success {
                if let data = result.result.data,
                   let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted]),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    print(jsonString)
                }
            } else {
                print("Error: \(result.result.error ?? "Unknown error")")
            }
        }
        
        print()
        
        // Display performance metrics
        print("Compile + Load: \(loadDuration.converted(to: .seconds).value.formatted(.number.precision(.fractionLength(2)))) sec")
        let numberFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))

        let promptLatencies = predictions.compactMap { $0.promptLatency?.converted(to: .milliseconds).value }
        if !promptLatencies.isEmpty {
            let averagePrompt = Measurement(value: promptLatencies.mean(), unit: UnitDuration.milliseconds)
            print("Prompt        : \(averagePrompt.value.formatted(numberFormat)) ms")
        }

        print("Generate      :", terminator: " ")

        let latencies = predictions.compactMap { $0.latency?.converted(to: .milliseconds).value }
        let average = Measurement(value: latencies.mean(), unit: UnitDuration.milliseconds)
        let stdev = Measurement(value: latencies.stdev(), unit: UnitDuration.milliseconds)
        print("\(average.value.formatted(numberFormat)) +/- \(stdev.value.formatted(numberFormat)) ms / token")

        let throughputs = predictions.compactMap { $0.latency?.converted(to: .seconds).value }.map { 1 / $0 }
        let averageThroughput = Measurement(value: throughputs.mean(), unit: UnitDuration.seconds)
        let stdevThroughput = Measurement(value: throughputs.stdev(), unit: UnitDuration.seconds)
        print("                \(averageThroughput.value.formatted(numberFormat)) +/- \(stdevThroughput.value.formatted(numberFormat)) token / sec")
    }
    
    private func outputJSONWithToolCalls(inputText: String, generatedText: String, toolCallResults: [ToolCallResult], loadDuration: Measurement<UnitDuration>, predictions: [Prediction]) {
        let promptLatencies = predictions.compactMap { $0.promptLatency?.converted(to: .milliseconds).value }
        let averagePrompt = promptLatencies.isEmpty ? nil : promptLatencies.mean()
        
        let latencies = predictions.compactMap { $0.latency?.converted(to: .milliseconds).value }
        let averageLatency = latencies.mean()
        let stdevLatency = latencies.stdev()
        
        let throughputs = predictions.compactMap { $0.latency?.converted(to: .seconds).value }.map { 1 / $0 }
        let averageThroughput = throughputs.mean()
        let stdevThroughput = throughputs.stdev()
        
        var performanceData: [String: Any] = [
            "compile_load_time_seconds": loadDuration.converted(to: .seconds).value,
            "generation_latency_ms": averageLatency,
            "generation_latency_stdev_ms": stdevLatency,
            "generation_throughput_tokens_per_sec": averageThroughput,
            "generation_throughput_stdev_tokens_per_sec": stdevThroughput,
            "tokens_generated": predictions.count
        ]
        
        if let prompt = averagePrompt {
            performanceData["prompt_latency_ms"] = prompt
        }
        
        // Convert tool call results to JSON format
        let toolCallsData = toolCallResults.map { result in
            var toolCallData: [String: Any] = [
                "tool_name": result.toolCall.name,
                "tool_parameters": result.toolCall.parameters,
                "success": result.result.success,
                "timestamp": ISO8601DateFormatter().string(from: result.timestamp)
            ]
            
            if let data = result.result.data {
                toolCallData["result"] = data
            }
            
            if let error = result.result.error {
                toolCallData["error"] = error
            }
            
            return toolCallData
        }
        
        let jsonOutput: [String: Any] = [
            "input_text": inputText,
            "generated_text": toolCallParser.extractTextContent(from: generatedText),
            "tool_calls": toolCallsData,
            "performance": performanceData
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: jsonOutput, options: [.prettyPrinted])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            }
        } catch {
            print("Error serializing JSON: \(error)")
        }
    }
    
    private func outputInteractiveJSONWithToolCalls(generatedText: String, toolCallResults: [ToolCallResult], predictions: [Prediction]) {
        let toolCallsData = toolCallResults.map { result in
            var toolCallData: [String: Any] = [
                "tool_name": result.toolCall.name,
                "tool_parameters": result.toolCall.parameters,
                "success": result.result.success,
                "timestamp": ISO8601DateFormatter().string(from: result.timestamp)
            ]
            
            if let data = result.result.data {
                toolCallData["result"] = data
            }
            
            if let error = result.result.error {
                toolCallData["error"] = error
            }
            
            return toolCallData
        }
        
        let jsonOutput: [String: Any] = [
            "generated_text": toolCallParser.extractTextContent(from: generatedText),
            "tool_calls": toolCallsData,
            "tokens_generated": predictions.count
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: jsonOutput, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            }
        } catch {
            print("Error serializing JSON: \(error)")
        }
    }
    
    private func outputStandard(generatedText: String, loadDuration: Measurement<UnitDuration>, predictions: [Prediction]) {
        print("\n")
        print(generatedText)
        print()

        print("Compile + Load: \(loadDuration.converted(to: .seconds).value.formatted(.number.precision(.fractionLength(2)))) sec")
        let numberFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))

        let promptLatencies = predictions.compactMap { $0.promptLatency?.converted(to: .milliseconds).value }
        if !promptLatencies.isEmpty {
            let averagePrompt = Measurement(value: promptLatencies.mean(), unit: UnitDuration.milliseconds)
            print("Prompt        : \(averagePrompt.value.formatted(numberFormat)) ms")
        }

        print("Generate      :", terminator: " ")

        let latencies = predictions.compactMap { $0.latency?.converted(to: .milliseconds).value }
        let average = Measurement(value: latencies.mean(), unit: UnitDuration.milliseconds)
        let stdev = Measurement(value: latencies.stdev(), unit: UnitDuration.milliseconds)
        print("\(average.value.formatted(numberFormat)) +/- \(stdev.value.formatted(numberFormat)) ms / token")

        let throughputs = predictions.compactMap { $0.latency?.converted(to: .seconds).value }.map { 1 / $0 }
        let averageThroughput = Measurement(value: throughputs.mean(), unit: UnitDuration.seconds)
        let stdevThroughput = Measurement(value: throughputs.stdev(), unit: UnitDuration.seconds)
        print("                \(averageThroughput.value.formatted(numberFormat)) +/- \(stdevThroughput.value.formatted(numberFormat)) token / sec")
    }
    
    private func outputJSON(inputText: String, generatedText: String, loadDuration: Measurement<UnitDuration>, predictions: [Prediction]) {
        let promptLatencies = predictions.compactMap { $0.promptLatency?.converted(to: .milliseconds).value }
        let averagePrompt = promptLatencies.isEmpty ? nil : promptLatencies.mean()
        
        let latencies = predictions.compactMap { $0.latency?.converted(to: .milliseconds).value }
        let averageLatency = latencies.mean()
        let stdevLatency = latencies.stdev()
        
        let throughputs = predictions.compactMap { $0.latency?.converted(to: .seconds).value }.map { 1 / $0 }
        let averageThroughput = throughputs.mean()
        let stdevThroughput = throughputs.stdev()
        
        var performanceData: [String: Any] = [
            "compile_load_time_seconds": loadDuration.converted(to: .seconds).value,
            "generation_latency_ms": averageLatency,
            "generation_latency_stdev_ms": stdevLatency,
            "generation_throughput_tokens_per_sec": averageThroughput,
            "generation_throughput_stdev_tokens_per_sec": stdevThroughput,
            "tokens_generated": predictions.count
        ]
        
        if let prompt = averagePrompt {
            performanceData["prompt_latency_ms"] = prompt
        }
        
        let jsonOutput: [String: Any] = [
            "input_text": inputText,
            "generated_text": generatedText,
            "performance": performanceData
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: jsonOutput, options: [.prettyPrinted])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            }
        } catch {
            print("Error serializing JSON: \(error)")
        }
    }
    
    private func outputInteractiveJSON(generatedText: String, predictions: [Prediction]) {
        let jsonOutput: [String: Any] = [
            "generated_text": generatedText,
            "tokens_generated": predictions.count
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: jsonOutput, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            }
        } catch {
            print("Error serializing JSON: \(error)")
        }
    }
    
    private func removeStopTokens(from tokens: [Int], eosTokens: [Int]) -> [Int] {
        var filteredTokens = tokens
        
        while !filteredTokens.isEmpty && eosTokens.contains(filteredTokens.last!) {
            filteredTokens.removeLast()
        }
        
        return filteredTokens
    }
    
    private func getEosTokens(from tokenizer: Tokenizer) -> [Int] {
        var eosTokens: [Int] = []
        
        if let eosToken = tokenizer.eosTokenId {
            eosTokens.append(eosToken)
        }
        
        let commonEosStrings = [
            "<|eot_id|>",
            "<|end_of_text|>",
            "<|endoftext|>",
            "</s>",
            "<|im_end|>"
        ]
        
        for eosString in commonEosStrings {
            let encoded = tokenizer.encode(text: eosString)
            if encoded.count == 1 {
                eosTokens.append(encoded[0])
            }
        }
        
        let commonEosTokenIds = [128009, 128001]
        eosTokens.append(contentsOf: commonEosTokenIds)
        
        return Array(Set(eosTokens))
    }
}
