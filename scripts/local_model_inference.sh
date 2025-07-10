#!/bin/bash

# llm-chat.sh - Simple test script for CoreML LLM CLI
# Usage: ./llm-chat.sh

set -e

# Test prompts
SYSTEM_PROMPT="You are a helpful coding assistant. Provide concise, accurate answers."
USER_PROMPT="Write a simple hello world program in Python."

echo "Testing CoreML LLM CLI with system and user prompts..."
echo "System prompt: $SYSTEM_PROMPT"
echo "User prompt: $USER_PROMPT"
echo "---"

# Run the LLMCLI with test prompts
swift run LLMCLI \
    --local-model-directory ~/.cache/huggingface/hub/models--smpanaro--Llama-3.2-1B-Instruct-CoreML/snapshots/f51990641585e06808c91bff7ea0213d326c8683 \
    --tokenizer-name meta-llama/Llama-3.2-1B \
    --output-format json \
    --system-prompt "$SYSTEM_PROMPT" \
    "$USER_PROMPT"
