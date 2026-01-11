# Test POST Request for /listen Endpoint

## Using curl command:

```bash
curl -X POST http://localhost:8000/listen \
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
  --output test_response.mp3
```

## Using curl with JSON file:

```bash
curl -X POST http://localhost:8000/listen \
  -H "Content-Type: application/json" \
  -d @test_api.json \
  --output test_response.mp3
```

## Using the test script:

```bash
./test_api.sh
```

## Play the audio response:

```bash
afplay test_response.mp3
```

## Expected Behavior:

1. The API will receive the text message
2. Gemini will extract important information (intent: help finding keys)
3. The message will be saved to MongoDB
4. Gemini will generate an assistance response
5. ElevenLabs will convert the response to speech
6. An MP3 audio file will be returned

## Request Body Structure:

- `text` (string): The user's message
- `vitals` (object, optional):
  - `heart_rate` (integer): Heart rate in BPM
  - `breathing_rate` (integer): Breathing rate per minute
  - `movement_score` (integer): Movement score (0-100)
  - `stress_detected` (boolean): Whether stress is detected

