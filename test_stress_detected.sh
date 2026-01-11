#!/bin/bash

# Test script for stress_detected query
# This demonstrates a POST request with stress_detected: true

BASE_URL="http://localhost:8000/listen"
OUTPUT_FILE="test_responses/stress_detected_response.mp3"

# Create test_responses directory if it doesn't exist
mkdir -p test_responses

echo "🧪 Testing Stress Detected Query"
echo "=================================="
echo ""

# Send POST request with stress_detected: true
echo "Sending request with stress_detected: true..."
echo ""

curl -X POST "$BASE_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "I cannot find my keys and I am really worried about missing my doctor'\''s appointment",
    "vitals": {
      "heart_rate": 95,
      "breathing_rate": 22,
      "movement_score": 85,
      "stress_detected": true
    }
  }' \
  --output "$OUTPUT_FILE" \
  --write-out "\nHTTP Status: %{http_code}\n" \
  --silent --show-error

# Check if response is audio or JSON error
if [ -f "$OUTPUT_FILE" ]; then
    file_size=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE" 2>/dev/null)
    if [ "$file_size" -lt 100 ]; then
        echo ""
        echo "Response appears to be JSON (error):"
        cat "$OUTPUT_FILE"
        echo ""
    else
        echo ""
        echo "✅ Audio response received (${file_size} bytes)"
        echo "Saved to: $OUTPUT_FILE"
        echo ""
        echo "To play the audio:"
        echo "  afplay $OUTPUT_FILE"
        echo ""
    fi
fi

echo ""
echo "Expected behavior:"
echo "- Backend should log: '⚠️  STRESS/DEMENTIA EPISODE DETECTED - Using calming approach'"
echo "- Database entry should have stress_detected: true"
echo "- Dashboard should show red background for this entry"
echo "- Response should be calming and reassuring"

