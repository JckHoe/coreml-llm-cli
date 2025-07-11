#!/bin/bash

# Test script for anonymizer tool validation
# This script tests the anonymizer tool with various inputs to ensure it works correctly

set -e

echo "📝 Testing anonymizer tool with sample inputs..."

swift run LLMCLI \
    --interactive \
    --system-prompt "Find names in the input text. For each name found, create a JSON mapping where the original name is the key and a completely different, unrelated name is the value. The replacement name must be different from the original. Return only JSON." \
    --local-model-directory ~/.cache/huggingface/hub/models--smpanaro--Llama-3.2-1B-Instruct-CoreML/snapshots/f51990641585e06808c91bff7ea0213d326c8683 \
    --enable-tools \
    --available-tools "anonymize_text" \
    --tokenizer-name meta-llama/Llama-3.2-1B \
    --output-format json 

