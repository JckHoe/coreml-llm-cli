swift run LLMCLI \
    --system-prompt "Find names, numbers, and specific values in the input text. Create a JSON object where each original value is mapped to a replacement value. Format: {\"John\": \"Robert\"}. Only return the JSON mapping." \
    --local-model-directory ~/.cache/huggingface/hub/models--smpanaro--Llama-3.2-1B-Instruct-CoreML/snapshots/f51990641585e06808c91bff7ea0213d326c8683 \
    --tokenizer-name meta-llama/Llama-3.2-1B \
    --output-format json \
    "I am John" 

