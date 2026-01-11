from fastapi import FastAPI
from fastapi.responses import Response
from pydantic import BaseModel
import requests
import os
import uvicorn
from dotenv import load_dotenv

load_dotenv()

print("API key loaded:", bool(os.getenv("ELEVENLABS_API_KEY")))

app = FastAPI()

ELEVENLABS_API_KEY = os.getenv("ELEVENLABS_API_KEY")
VOICE_ID = "TxGEqnHWrfWFTfGW9XjX"

class VoiceData(BaseModel):
    text: str

@app.get("/")
def read_root():
    return {"status": "Server is ONLINE and ready for signals."}

@app.post("/listen")
def receive_voice(data: VoiceData):
    print("------------------------------------------------")
    print(f"🎤 IPHONE SAID: {data.text}")
    print("------------------------------------------------")

    # 1. Ask ElevenLabs to speak the user's text (Echo)
    # You can change 'data.text' to any response string you want the AI to say
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}"
    
    headers = {
        "Accept": "audio/mpeg",
        "Content-Type": "application/json",
        "xi-api-key": ELEVENLABS_API_KEY
    }
    
    payload = {
        "text": f"You said: {data.text}", # Adding prefix so you know it's working
        "model_id": "eleven_multilingual_v2",
        "voice_settings": {"stability": 0.5, "similarity_boost": 0.5}
    }

    print("🗣️ Generating Audio with ElevenLabs...")
    response = requests.post(url, json=payload, headers=headers)

    if response.status_code == 200:
        print("✅ Audio received! Streaming to iPhone...")
        return Response(content=response.content, media_type="audio/mpeg")
    else:
        print(f"❌ ElevenLabs Error: {response.text}")
        return {"status": "error", "message": "Failed to generate audio"}

@app.post("/is-there")
def is_there():
    """Checks if user is present (triggered by face loss)."""
    print("\n------------------------------------------------")
    print("⚠️  FACE LOST DETECTED - Checking in...")
    print("------------------------------------------------")
    
    text_to_say = "Are you still there? I can't see you."
    
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}"
    headers = {
        "Accept": "audio/mpeg",
        "Content-Type": "application/json",
        "xi-api-key": ELEVENLABS_API_KEY
    }
    payload = {
        "text": text_to_say,
        "model_id": "eleven_multilingual_v2",
        "voice_settings": {"stability": 0.5, "similarity_boost": 0.5}
    }
    
    response = requests.post(url, json=payload, headers=headers)
    
    if response.status_code == 200:
        print("✅ sending 'Are you there' audio...")
        return Response(content=response.content, media_type="audio/mpeg")
    
    return {"status": "error"}

@app.post("/speak")
def speak(data: VoiceData):
    response = requests.post(
        f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}",
        headers={
            "xi-api-key": ELEVENLABS_API_KEY,
            "Content-Type": "application/json",
            "Accept": "audio/mpeg"
        },
        json={
            "text": data.text,
            "model_id": "eleven_multilingual_v2", 
            "voice_settings": {
                "stability": 0.5,
                "similarity_boost": 0.5
            }
        }
    )

    if response.status_code != 200:
        print("ElevenLabs status:", response.status_code)
        print("ElevenLabs error:", response.text)
        return {"error": response.text}

    return Response(
        content=response.content,
        media_type="audio/mpeg",
        headers={
            "Content-Length": str(len(response.content))
        }
    )

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
