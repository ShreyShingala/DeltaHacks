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
VOICE_ID = "21m00Tcm4TlvDq8ikWAM" 

class VoiceData(BaseModel):
    text: str

@app.get("/")
def read_root():
    return {"status": "Server is ONLINE and ready for signals."}

@app.post("/listen")
def receive_voice(data: VoiceData):
    print("------------------------------------------------")
    print(f"IPHONE SAID: {data.text}")
    print("------------------------------------------------")
    return {"status": "received", "you_said": data.text}

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
