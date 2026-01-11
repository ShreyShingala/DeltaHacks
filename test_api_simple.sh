#!/bin/bash

# Simple test script that shows the error response

echo "📤 Testing /listen endpoint..."
echo ""

curl -X POST http://localhost:8000/listen \
  -H "Content-Type: application/json" \
  -d @test_api.json \
  -i

echo ""
echo ""
echo "💡 Tip: Check your server logs to see the ElevenLabs error details"
echo "💡 Make sure ELEVENLABS_API_KEY is set in your .env file"

