import Foundation
import ArgumentParser
import Tokenizers
import Hub
import CoreML

@main
struct CLI: AsyncParsableCommand {
    @Option(help: "Huggingface repo ID. e.g. smpanaro/Llama-2-7b-CoreML")
    var repoID: String? = nil

    @Option(
        help: "The directory containing the model's mlmodelc files.",
        completion: .file(), transform: URL.init(fileURLWithPath:))
    var localModelDirectory: URL?

    @Option(help: "The model filename prefix, to differentiate when there are multiple models in a folder.")
    var localModelPrefix: String?

    @Option(help: "KV cache processor model filename, located in the model directory.")
    var cacheProcessorModelName: String = "cache-processor.mlmodelc"

    @Option(help: "Logit processor model filename, located in the model directory.")
    var logitProcessorModelName: String = "logit-processor.mlmodelc"

    @Option(help: "Tokenizer name on huggingface.")
    var tokenizerName: String?

    @Option(help: "System prompt for the conversation.")
    var systemPrompt: String?
    
    @Option(help: "Single text input (for backward compatibility).")
    var inputText: String?
    
    @Argument(help: "User prompt/question.")
    var userPrompt: String = "Hello! How can I help you today?"

    @Option(help: "Maximum number of new tokens to generate.")
    var maxNewTokens: Int = 2000

    @Option(help: "Print verbose logs for debugging.")
    var verbose: Bool = false
    
    @Option(help: "Output format: 'standard' or 'json'.")
    var outputFormat: String = "standard"
    
    @Flag(help: "Run in interactive mode, reading from STDIN and writing to STDOUT.")
    var interactive: Bool = false
    
    @Flag(help: "Suppress all loading and compilation messages.")
    var quiet: Bool = false
    
    @Flag(help: "Enable tool calling functionality.")
    var enableTools: Bool = false
    
    @Option(help: "Comma-separated list of tools to enable (default: all available tools).")
    var availableTools: String?

    mutating func run() async throws {
        var modelDirectory = localModelDirectory
        if let repoID {
            modelDirectory = try await downloadModel(repoID: repoID)
        }

        guard let modelDirectory else {
            print("Either --repoID or --localModelDirectory must be provided.")
            return
        }

        guard let tokenizerName = tokenizerName ?? inferTokenizer() else {
            print("Unable to infer tokenizer. Please provide --tokenizerName.")
            return
        }

        let pipeline = try ModelPipeline.from(
            folder: modelDirectory,
            modelPrefix: localModelPrefix,
            cacheProcessorModelName: cacheProcessorModelName,
            logitProcessorModelName: logitProcessorModelName
        )
        if !quiet {
            if !interactive {
                print(pipeline)
            } else {
                fputs("\(pipeline)\n", stderr)
            }
        }

        let tokenizer = try await AutoTokenizer.from(cached: tokenizerName, hubApi: .init(hfToken: HubApi.defaultToken()))
        if verbose && !quiet { 
            if !interactive {
                print("Tokenizer \(tokenizerName) loaded.")
            } else {
                fputs("Tokenizer \(tokenizerName) loaded.\n", stderr)
            }
        }

        // Setup tool manager if tools are enabled
        var toolManager: ToolManager? = nil
        if enableTools {
            toolManager = ToolManager.withDefaultTools()
            
            // Filter tools if specific ones are requested
            if let availableToolsStr = availableTools {
                let requestedTools = availableToolsStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                let allTools = toolManager!.getTools()
                
                // Clear all tools and add only requested ones
                toolManager!.clearTools()
                
                for toolName in requestedTools {
                    if let tool = allTools.first(where: { $0.name == toolName }) {
                        toolManager!.registerTool(tool)
                    } else {
                        print("Warning: Tool '\(toolName)' not found. Available tools: \(allTools.map { $0.name }.joined(separator: ", "))")
                    }
                }
            }
            
            if verbose && !quiet {
                let toolNames = toolManager!.getTools().map { $0.name }.joined(separator: ", ")
                if !interactive {
                    print("Tools enabled: \(toolNames)")
                } else {
                    fputs("Tools enabled: \(toolNames)\n", stderr)
                }
            }
        }

        let generator = TextGenerator(pipeline: pipeline, tokenizer: tokenizer, toolManager: toolManager)
        
        if interactive {
            pipeline.isInteractiveMode = true
            pipeline.isQuiet = quiet
            try pipeline.load()
            
            // Signal that models are ready for interactive mode
            if !quiet {
                fputs("Ready for input.\n", stderr)
                fflush(stderr)
            }
            
            try await runInteractiveMode(generator: generator)
        } else {
            pipeline.isQuiet = quiet
            try await runSingleShotMode(generator: generator)
        }
    }
    
    private func runSingleShotMode(generator: TextGenerator) async throws {
        let formattedPrompt: String
        
        if let inputText = inputText {
            if enableTools, let toolManager = createToolManager() {
                formattedPrompt = ChatTemplateFormatter.formatLlamaPromptWithTools(systemPrompt: systemPrompt, userPrompt: inputText, toolManager: toolManager)
            } else {
                formattedPrompt = ChatTemplateFormatter.formatSingleInput(inputText)
            }
        } else {
            if enableTools, let toolManager = createToolManager() {
                formattedPrompt = ChatTemplateFormatter.formatLlamaPromptWithTools(systemPrompt: systemPrompt, userPrompt: userPrompt, toolManager: toolManager)
            } else {
                formattedPrompt = ChatTemplateFormatter.formatLlamaPrompt(systemPrompt: systemPrompt, userPrompt: userPrompt)
            }
        }
        
        let isJsonOutput = outputFormat.lowercased() == "json"
        try await generator.generate(text: formattedPrompt, maxNewTokens: maxNewTokens, outputFormat: isJsonOutput ? .json : .standard)
    }
    
    private func runInteractiveMode(generator: TextGenerator) async throws {
        let isJsonOutput = outputFormat.lowercased() == "json"
        
        while let line = readLine() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmedLine.isEmpty {
                continue
            }
            
            if trimmedLine.lowercased() == "quit" || trimmedLine.lowercased() == "exit" {
                break
            }
            
            let formattedPrompt: String
            if enableTools, let toolManager = createToolManager() {
                formattedPrompt = ChatTemplateFormatter.formatLlamaPromptWithTools(systemPrompt: systemPrompt, userPrompt: trimmedLine, toolManager: toolManager)
            } else {
                formattedPrompt = ChatTemplateFormatter.formatLlamaPrompt(systemPrompt: systemPrompt, userPrompt: trimmedLine)
            }
            
            try await generator.generateInteractive(text: formattedPrompt, maxNewTokens: maxNewTokens, outputFormat: isJsonOutput ? .json : .standard)
        }
    }
    
    private func createToolManager() -> ToolManager? {
        guard enableTools else { return nil }
        
        let toolManager = ToolManager.withDefaultTools()
        
        // Filter tools if specific ones are requested
        if let availableToolsStr = availableTools {
            let requestedTools = availableToolsStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let allTools = toolManager.getTools()
            
            // Clear all tools and add only requested ones
            toolManager.clearTools()
            
            for toolName in requestedTools {
                if let tool = allTools.first(where: { $0.name == toolName }) {
                    toolManager.registerTool(tool)
                }
            }
        }
        
        return toolManager
    }

    func inferTokenizer() -> String? {
        switch (repoID ?? localModelPrefix ?? localModelDirectory?.lastPathComponent)?.lowercased() ?? "" {
        case let str where str.contains("llama-2-7b"):
            return "pcuenq/Llama-2-7b-chat-coreml"
        case let str where str.contains( "llama-3.2-1b"):
            return "meta-llama/Llama-3.2-1B"
        case let str where str.contains( "llama-3.2-3b"):
            return "meta-llama/Llama-3.2-3B"
        default:
            return nil
        }
    }

    /// Download a model and return the local directory URL.
    func downloadModel(repoID: String) async throws -> URL {
        let hub = HubApi(hfToken: HubApi.defaultToken())
        let repo = Hub.Repo(id: repoID, type: .models)

        let mlmodelcs = ["Llama*.mlmodelc/*", "logit*", "cache*"]
        let filenames = try await hub.getFilenames(from: repo, matching: mlmodelcs)

        let localURL = hub.localRepoLocation(repo)
        print(localURL.path())

        let localFileURLs = filenames.map {
            localURL.appending(component: $0)
        }
        let anyNotExists = localFileURLs.filter {
            !FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
        }.count > 0

        let newestTimestamp = localFileURLs.filter {
            FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
        }.compactMap {
           let attrs = try! FileManager.default.attributesOfItem(atPath: $0.path(percentEncoded: false))
           return attrs[.modificationDate] as? Date
        }.max() ?? Date.distantFuture
        let lastUploadDate = Date(timeIntervalSince1970: 1723688450)
        let isStale = repoID == "smpanaro/Llama-2-7b-coreml" && newestTimestamp < lastUploadDate

        if isStale {
            print("⚠️ You have an old model downloaded. Please move the following directory to the Trash and try again:")
            print(localURL.path())
            throw CLIError.staleFiles
        }

        let needsDownload = anyNotExists || isStale
        guard needsDownload else { return localURL }

        print("Downloading from \(repoID)...")
        if filenames.count == 0 {
            throw CLIError.noModelFilesFound
        }

        let downloadDir = try await hub.snapshot(from: repo, matching: mlmodelcs) { progress in
            let percent = progress.fractionCompleted * 100
            if !progress.isFinished {
                print("\(percent.formatted(.number.precision(.fractionLength(0))))%", terminator: "\r")
                fflush(stdout)
            }
        }
        print("Done.")
        print("Downloaded to \(downloadDir.path())")
        return downloadDir
    }
}

enum CLIError: Error {
    case noModelFilesFound
    case staleFiles
}
