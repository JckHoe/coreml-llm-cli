swift run LLMCLI \
    --interactive \
    --system-prompt "Find names in the input text. For each name found, create a JSON mapping where the original name is the key and a completely different, unrelated name is the value. The replacement name must be different from the original. Return only JSON." \
    --repo-id smpanaro/Llama-3.2-1B-Instruct-CoreML \
    --output-format json 

