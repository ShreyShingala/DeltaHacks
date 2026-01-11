# Debugging the /listen Endpoint

## Current Issue
The API is returning `{"status":"error","message":"Failed to generate audio"}` which means ElevenLabs API call is failing.

## How to Debug

### 1. Check Server Console
Look at the terminal where your FastAPI server is running. You should see:
```
❌ ElevenLabs Error: <actual error message>
```

Common errors:
- `401 Unauthorized` - Invalid API key
- `429 Too Many Requests` - Rate limit exceeded
- `400 Bad Request` - Invalid voice ID or request format
- Network errors - Connection issues

### 2. Verify API Key is Loaded
When the server starts, it should print:
```
API key loaded: True
```
If it says `False`, your `ELEVENLABS_API_KEY` is not set in the `.env` file.

### 3. Test the Pipeline (without ElevenLabs)
Check if the rest of the pipeline works:
- Ollama extraction
- MongoDB save
- Ollama response generation

Look for these messages in server logs:
- `🧠 Processing with Ollama...`
- `📊 EXTRACTED INFO: ...`
- `💾 Saving to MongoDB...`
- `✨ Generating Ollama response...`
- `💬 Ollama SAYS: ...`

### 4. Quick Tests

**Test if server is running:**
```bash
curl http://localhost:8000/
```

**Test the full endpoint (see JSON response):**
```bash
./test_listen_text.sh
```

**Check MongoDB to see if data was saved:**
```bash
python3 check_db.py
```

### 5. Common Fixes

**Missing API Key:**
- Add `ELEVENLABS_API_KEY=your_key_here` to `.env` file
- Restart the server

**Invalid API Key:**
- Verify key at https://elevenlabs.io/
- Make sure there are no extra spaces or quotes

**Voice ID Invalid:**
- Current voice ID: `TxGEqnHWrfWFTfGW9XjX`
- Check if this voice exists in your ElevenLabs account

**Rate Limiting:**
- Free tier has limited requests
- Wait a few minutes and try again

