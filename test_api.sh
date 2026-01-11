#!/bin/bash

# Test POST request for /listen endpoint
# Tests the API with a message about missing keys

echo "📤 Sending request to /listen endpoint..."
echo ""

response=$(curl -s -X POST http://localhost:8000/listen \
  -H "Content-Type: application/json" \
  -d '{
    "text": "I don'\''t know where my keys are, can you help me?",
    "vitals": {
      "heart_rate": 60,
      "breathing_rate": 10,
      "movement_score": 10,
      "stress_detected": false
    }
  }' \
  -w "\n%{http_code}" \
  --output test_response.raw)

http_code=$(echo "$response" | tail -n 1)
content_type=$(curl -s -I -X POST http://localhost:8000/listen \
  -H "Content-Type: application/json" \
  -d '{"text":"test"}' 2>/dev/null | grep -i content-type | cut -d' ' -f2 | tr -d '\r\n')

echo "HTTP Status Code: $http_code"
echo ""

# Check if response is JSON (error) or audio
if head -c 1 test_response.raw | grep -q '{'; then
  echo "❌ Error response received (JSON):"
  cat test_response.raw
  echo ""
  echo "⚠️  The API returned an error. Check server logs for details."
  echo "Common issues:"
  echo "  - ElevenLabs API key not set or invalid"
  echo "  - Network connectivity issues"
  echo "  - Voice ID invalid"
  rm -f test_response.raw
else
  # It's audio - rename and play
  mv test_response.raw test_response.mp3
  echo "✅ Audio response received!"
  echo "📁 Saved to test_response.mp3"
  echo ""
  echo "🎵 Playing audio..."
  afplay test_response.mp3
fi

