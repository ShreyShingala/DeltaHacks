# main.py
from fastapi import FastAPI
from pydantic import BaseModel
import uvicorn

app = FastAPI()

# This defines the data we expect from the iPhone
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

if __name__ == "__main__":
    # 0.0.0.0 is crucial! It lets other devices (your phone) see the server.
    uvicorn.run(app, host="0.0.0.0", port=8000)