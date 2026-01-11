# Ollama Setup Guide

## Installation

1. **Install Ollama:**
   - Visit https://ollama.ai
   - Download and install Ollama for your operating system
   - Or use: `brew install ollama` on macOS

2. **Start Ollama server:**
   ```bash
   ollama serve
   ```
   This starts the server on `http://localhost:11434` (default)

3. **Pull a model:**
   ```bash
   # Recommended models:
   ollama pull llama3.2        # Good balance of speed and quality (default)
   ollama pull llama3.1:8b     # Faster, smaller
   ollama pull llama3.1:70b    # Slower, higher quality
   ollama pull mistral         # Alternative model
   ollama pull gemma2:2b       # Very fast, small model
   ```

## Configuration

Add to your `.env` file (optional - defaults shown):
```
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_MODEL=llama3.2
```

## Testing

1. Make sure Ollama is running:
   ```bash
   curl http://localhost:11434/api/tags
   ```

2. Test a simple request:
   ```bash
   curl http://localhost:11434/api/generate -d '{
     "model": "llama3.2",
     "prompt": "Hello, how are you?",
     "stream": false
   }'
   ```

3. Run your FastAPI server and test the `/listen` endpoint as usual.

## Notes

- Ollama runs completely locally - no API keys needed!
- Models are downloaded to `~/.ollama/models/`
- First request may be slower as the model loads
- Responses may vary slightly from Gemini, but functionality is the same

