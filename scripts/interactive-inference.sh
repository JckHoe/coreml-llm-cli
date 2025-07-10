set -e

# Test prompts
SYSTEM_PROMPT="You are a helpful coding assistant. Provide concise, accurate answers."
USER_PROMPT="Write a simple hello world program in Python."

# Run the LLMCLI with test prompts
swift run LLMCLI \
    --interactive \
    --quiet \
    --local-model-directory ~/.cache/huggingface/hub/models--smpanaro--Llama-3.2-1B-Instruct-CoreML/snapshots/f51990641585e06808c91bff7ea0213d326c8683 \
    --tokenizer-name meta-llama/Llama-3.2-1B \
    --output-format json \
    --system-prompt "$SYSTEM_PROMPT"

printf "What is 2+2?\nWhat is 3+3?\n" | swift run LLMCLI --interactive --quiet
  --local-model-directory ~/.cache/huggingface/hub/models--smpanaro--Llama-3.2-1B-Instruct-CoreML/snapshots/f51990641585e06808c91bff7ea0213d326c8683 --tokenizer-name meta-llama/Llama-3.2-1B
