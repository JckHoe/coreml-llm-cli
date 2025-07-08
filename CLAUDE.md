# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Run Commands

This is a Swift package that builds an executable CLI for running CoreML LLM models on Apple Silicon.

### Build and Run
```bash
# Build and run with default parameters
swift run LLMCLI

# Build and run with specific model
swift run LLMCLI --repo-id smpanaro/Llama-2-7b-coreml

# Build optimized release version for performance testing
swift run -c release LLMCLI --repo-id smpanaro/Llama-2-7b-coreml --max-new-tokens 80

# Use local model directory
swift run LLMCLI --local-model-directory /path/to/model --local-model-prefix "model_name"
```

### Key CLI Arguments
- `--repo-id`: HuggingFace repository ID for downloading models
- `--local-model-directory`: Path to local model directory
- `--local-model-prefix`: Model filename prefix for disambiguation
- `--max-new-tokens`: Maximum number of tokens to generate (default: 60)
- `--verbose`: Enable verbose logging

## Architecture Overview

This is a high-performance CoreML LLM inference engine with several key optimizations:

### Core Components

1. **ModelPipeline** (`Sources/Kit/ModelPipeline.swift`): Central orchestrator that manages chunked model execution
   - Manages multiple MLModel chunks for memory efficiency
   - Coordinates async KV cache updates between chunks
   - Handles model loading/unloading and compute unit configuration

2. **TextGenerator** (`Sources/Kit/TextGenerator.swift`): High-level text generation interface
   - Wraps ModelPipeline with tokenization
   - Provides streaming token generation
   - Reports performance metrics (latency, throughput)

3. **KVCacheProcessor** (`Sources/Kit/KVCacheProcessor.swift`): Async KV cache management
   - Updates KV caches asynchronously between model chunks
   - Optimizes memory usage and reduces inference latency

4. **LogitProcessor** (`Sources/Kit/LogitProcessor.swift`): Token selection from model outputs
   - Handles chunked logit processing for large vocabularies
   - Implements argmax token selection

### Key Optimizations

- **Model Chunking**: Models are split into smaller chunks (embedding + N transformer blocks + LM head) for faster loading and async cache processing
- **IOSurface-backed Arrays**: Uses CVPixelBuffer/IOSurface for MLMultiArrays to avoid CPU-ANE memory copies
- **Tensor Reshaping**: Reshapes tensors from (B,C,1,64) to (B,C,8,8) for ~20% faster MLP convolutions
- **Async KV Cache Updates**: KV cache updates happen asynchronously while next chunk executes

### Model File Structure

Models should follow this naming convention:
- `${MODEL_PREFIX}_chunk${CHUNK_NUMBER}.mlmodelc` (e.g., `Llama-2-7b_chunk0.mlmodelc`)
- `cache-processor.mlmodelc` (KV cache processor)
- `logit-processor.mlmodelc` (token selection)

### Compute Configuration

- First chunk: CPU-only (contains operations incompatible with ANE)
- Remaining chunks: CPU + Neural Engine for optimal performance
- Requires macOS 14+ for Neural Engine support

### Dependencies

- Swift 5.9+
- swift-transformers (HuggingFace model downloading and tokenization)
- swift-argument-parser (CLI argument parsing)
- CoreML framework (model inference)

### Performance Testing

Use release builds for accurate performance measurements:
```bash
swift run -c release LLMCLI --repo-id smpanaro/Llama-2-7b-coreml --max-new-tokens 80
```

The CLI reports compilation time, prompt processing latency, and token generation throughput with standard deviation.