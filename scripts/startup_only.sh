echo "Startup only"
swift run LLMCLI \
    --interactive \
    --local-model-directory ~/.cache/huggingface/hub/models--smpanaro--Llama-3.2-1B-Instruct-CoreML/snapshots/f51990641585e06808c91bff7ea0213d326c8683 \
    --tokenizer-name meta-llama/Llama-3.2-1B 

