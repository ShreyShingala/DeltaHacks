from fastapi import FastAPI
from fastapi.responses import Response
from pydantic import BaseModel
import requests
import os
import uvicorn
from dotenv import load_dotenv
from db import save_event, get_context_for_user
from gemini_client import extract_important_info, generate_assistance

load_dotenv()

print("API key loaded:", bool(os.getenv("ELEVENLABS_API_KEY")))

app = FastAPI()

ELEVENLABS_API_KEY = os.getenv("ELEVENLABS_API_KEY")
VOICE_ID = "TxGEqnHWrfWFTfGW9XjX"
DEFAULT_USER = os.getenv("PRESAGE_USER", "alice")

class Vitals(BaseModel):
    heart_rate: int = None
    breathing_rate: int = None
    movement_score: int = None
    stress_detected: bool = False

class VoiceData(BaseModel):
    text: str
    vitals: Vitals = None

@app.get("/")
def read_root():
    return {"status": "Server is ONLINE and ready for signals."}

@app.post("/listennah")
def receive_voice(data: VoiceData):
    print("------------------------------------------------")
    print(f"🎤 IPHONE SAID: {data.text}")
    print("------------------------------------------------")
    return {"status": "received", "you_said": data.text}

@app.post("/listenold")
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

@app.post("/listen")
def receive_voice(data: VoiceData):
    print("------------------------------------------------")
    print(f"🎤 IPHONE SAID: {data.text}")
    print("------------------------------------------------")

    # 1. Send to Gemini to extract important info and create bullet points
    print("🧠 Processing with Gemini...")
    extracted_info = extract_important_info(data.text)
    print(f"📊 EXTRACTED INFO: {extracted_info}")
    
    # Add original_message to extracted_info so frontend can access it
    extracted_info["original_message"] = data.text
    
    # 2. Save the extracted info to MongoDB
    try:
        print("💾 Saving to MongoDB...")
        doc_id = save_event(DEFAULT_USER, extracted_info)
        print(f"✅ Saved to database with ID: {doc_id}")
    except Exception as e:
        print(f"❌ Database save failed: {e}")
        # Continue even if DB save fails
    
    # 3. Generate a summary response using Gemini
    print("✨ Generating Gemini response...")
    # Get recent context for more informed responses
    try:
        context = get_context_for_user(DEFAULT_USER, limit=5)
    except Exception as e:
        print(f"⚠️  Could not retrieve context from DB: {e}")
        context = []  # Use empty context if DB fails
    
    # Check if user is experiencing stress/dementia episode
    stress_detected = False
    if data.vitals and data.vitals.stress_detected:
        stress_detected = True
        print("                     ⚠️  STRESS/DEMENTIA EPISODE DETECTED - Using calming approach")
        print(data.vitals)
        print("------------------------------------------------")
        
    
    context_info = {
        "user": DEFAULT_USER,
        "recent_events": context,
        "total_events": len(context),
        "current_message": data.text,
        "extracted": extracted_info,
        "stress_detected": stress_detected,
        "vitals": data.vitals.dict() if data.vitals else None
    }
    
    gemini_message = generate_assistance(DEFAULT_USER, context_info)
    print(f"💬 GEMINI SAYS: {gemini_message}")
    
    # 4. Send Gemini's response to ElevenLabs for TTS
    print("🗣️ Generating Audio with ElevenLabs...")
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}"
    
    headers = {
        "Accept": "audio/mpeg",
        "Content-Type": "application/json",
        "xi-api-key": ELEVENLABS_API_KEY
    }
    
    payload = {
        "text": gemini_message,
        "model_id": "eleven_multilingual_v2",
        "voice_settings": {"stability": 0.5, "similarity_boost": 0.5}
    }

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
    # Write data.text to MongoDB database
    event_data = {
        "original_message": data.text,
        "intent": "speak",
        "raw": data.text
    }
    save_event(DEFAULT_USER, event_data)
    print(f"💾 Saved to DB: {data.text[:50]}...")
    
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
