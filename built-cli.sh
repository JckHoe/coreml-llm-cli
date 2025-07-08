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
./LLMCLI \
    --repo-id smpanaro/Llama-3.2-1B-Instruct-CoreML \
    --system-prompt "$SYSTEM_PROMPT" \
    "$USER_PROMPT"
