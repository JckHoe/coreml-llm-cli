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
    // var strategy: Strategy = .argmax // etc.

    init(pipeline: ModelPipeline, tokenizer: Tokenizer) {
        self.pipeline = pipeline
        self.tokenizer = tokenizer
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

        // Get multiple EOS tokens
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
        
        // Get only the newly generated tokens (exclude input tokens)
        let allTokens = predictions.last?.allTokens ?? tokens
        let newTokens = Array(allTokens.suffix(from: tokens.count))
        let generatedText = tokenizer.decode(tokens: newTokens)
        let fullText = tokenizer.decode(tokens: allTokens)
        
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
    
    private func getEosTokens(from tokenizer: Tokenizer) -> [Int] {
        var eosTokens: [Int] = []
        
        // Add the standard EOS token
        if let eosToken = tokenizer.eosTokenId {
            eosTokens.append(eosToken)
        }
        
        // Add common end-of-sequence tokens
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
        
        // Add common Llama EOS token IDs as fallback
        let commonEosTokenIds = [128009, 128001] // <|eot_id|>, <|end_of_text|>
        eosTokens.append(contentsOf: commonEosTokenIds)
        
        return Array(Set(eosTokens)) // Remove duplicates
    }
}
