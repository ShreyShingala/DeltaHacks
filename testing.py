# main.py
from fastapi import FastAPI
from pydantic import BaseModel
import uvicorn

import os

from gemini_client import extract_important_info, generate_assistance
from db import save_event, get_context_for_user

# For the hackathon, use a single default account for all messages
DEFAULT_USER = os.getenv("PRESAGE_USER", "alice")

app = FastAPI()

# This defines simple request shapes
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
    return {"status": "received", "you_said": data.text}


@app.post("/voice-request")
def voice_request(data: VoiceData):
    """Process voice input: extract important info via Gemini, store in DB, and print."""
    message = data.text
    print("\n" + "="*60)
    print(f"📥 VOICE REQUEST: {message}")
    
    # Extract important information using Gemini
    extracted = extract_important_info(message)
    
    # Store in database
    save_event(DEFAULT_USER, extracted)
    
    # Print extracted info to terminal
    print(f"📊 EXTRACTED INFO: {extracted}")
    print("="*60 + "\n")
    
    return {
        "status": "processed",
        "extracted_info": extracted,
        "stored": True
    }


@app.post("/is-there")
def is_there():
    """Lightweight healthcheck for remote clients (phone) to verify server reachability."""
    return {"status": "ok", "service": "presage", "message": "server reachable"}


@app.post("/assistance")
def assistance():
    """Generate calming assistance messages using all stored context from database."""
    # Get all stored context for the user
    context = get_context_for_user(DEFAULT_USER, limit=20)
    
    # Prepare context for Gemini
    context_summary = {
        "user": DEFAULT_USER,
        "recent_events": context,
        "total_events": len(context)
    }
    
    # Generate assistance message
    message = generate_assistance(DEFAULT_USER, context_summary)
    
    print("\n" + "="*60)
    print(f"🤝 ASSISTANCE REQUEST for {DEFAULT_USER}")
    print(f"📋 Context: {len(context)} recent events")
    print(f"💬 Response: {message}")
    print("="*60 + "\n")
    
    return {
        "assistance_message": message,
        "context_used": len(context)
    }


if __name__ == "__main__":
    # 0.0.0.0 is crucial! It lets other devices (your phone) see the server.
    uvicorn.run(app, host="0.0.0.0", port=8000)