#!/bin/bash
set -e

echo "Testing interactive mode with piped input..."

# Test 1: Simple math questions
echo "Test 1: Math questions"
printf "What is 2+2?\nWhat is 3+3?\n" | swift run LLMCLI \
    --interactive \
    --local-model-directory ~/.cache/huggingface/hub/models--smpanaro--Llama-3.2-1B-Instruct-CoreML/snapshots/f51990641585e06808c91bff7ea0213d326c8683 \
    --tokenizer-name meta-llama/Llama-3.2-1B \
    --max-new-tokens 15

echo -e "\n\nTest 2: System prompt test"
echo "I am John" | swift run LLMCLI \
    --interactive \
    --system-prompt "You are great at anonymizing PII, you are to return a list of replacement key values pairs for replacing sensitive information from the given text with another value. Example given user prompt with personal name replacement it with another placeholder value. Always return in JSON format and the list of replacement values in a dictionary" \
    --local-model-directory ~/.cache/huggingface/hub/models--smpanaro--Llama-3.2-1B-Instruct-CoreML/snapshots/f51990641585e06808c91bff7ea0213d326c8683 \
    --tokenizer-name meta-llama/Llama-3.2-1B \
    --output-format json 

echo -e "\n\nTest 3: JSON output format"
echo "Hello world" | swift run LLMCLI \
    --interactive \
    --output-format json \
    --local-model-directory ~/.cache/huggingface/hub/models--smpanaro--Llama-3.2-1B-Instruct-CoreML/snapshots/f51990641585e06808c91bff7ea0213d326c8683 \
    --tokenizer-name meta-llama/Llama-3.2-1B \
    --max-new-tokens 10
