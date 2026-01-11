#!/bin/bash

# Test /listen endpoint but return JSON instead of audio to see the full response

echo "📤 Testing /listen endpoint (expecting JSON response)..."
echo ""

curl -X POST http://localhost:8000/listen \
  -H "Content-Type: application/json" \
  -d @test_api.json \
  -s | python3 -m json.tool 2>/dev/null || curl -X POST http://localhost:8000/listen \
  -H "Content-Type: application/json" \
  -d @test_api.json

echo ""
echo ""
echo "💡 To see the full debugging info, check your server console/terminal"
echo "💡 The server should print:"
echo "   - 🧠 Processing with Gemini..."
echo "   - 📊 EXTRACTED INFO: ..."
echo "   - 💾 Saving to MongoDB..."
echo "   - ✨ Generating Gemini response..."
echo "   - 💬 GEMINI SAYS: ..."
echo "   - 🗣️ Generating Audio with ElevenLabs..."
echo "   - ❌ ElevenLabs Error: <actual error message>"

