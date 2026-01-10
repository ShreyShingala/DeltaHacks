import os
import json
from dotenv import load_dotenv
import google.generativeai as genai

load_dotenv()

GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")
if GOOGLE_API_KEY:
    genai.configure(api_key=GOOGLE_API_KEY)


def _call_gemini(prompt: str, max_tokens: int = 256) -> str:
    """Call Google Gemini using official SDK. Returns text response.
    If API key not configured, returns a fallback message.
    """
    if not GOOGLE_API_KEY:
        # Fallback for local dev without API key
        return json.dumps({"intent": "note", "raw": prompt})

    try:
        model = genai.GenerativeModel('gemini-pro')
        response = model.generate_content(prompt)
        return response.text
    except Exception as e:
        print(f"Gemini API error: {e}")
        return json.dumps({"error": str(e), "raw": prompt})


def extract_important_info(message: str) -> dict:
    """Ask the model to extract important fields from a free-form message.

    Returns a dict with extracted fields when possible; always returns a dict.
    """
    prompt = (
        "Extract important information from the user's message and return valid JSON only. "
        "Return keys (when present): intent, entities, stress_level, location, time, notes. "
        f"User message: '''{message}'''"
    )
    text = _call_gemini(prompt, max_tokens=256)

    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict):
            return parsed
    except Exception:
        pass

    # If parsing failed, return a minimal structure
    return {"raw": message}


def generate_assistance(user_name: str, context_info: dict) -> str:
    """Produce a short, calm assistance message using context_info.

    The prompt is intentionally small: the app should later use a low-latency Gemini Flash model.
    """
    prompt = (
        "You are a calm, gentle assistant helping someone who may be experiencing stress or confusion. "
        "Using the provided context, generate a few short, reassuring sentences to help ground them. "
        "Tell them where they are, what time it is, and what they should do next. Be warm, clear, and kind.\n\n"
        f"User: {user_name}\nContext: {json.dumps(context_info)}\n\nOutput:" 
    )
    text = _call_gemini(prompt, max_tokens=128)
    return (text or "Take a deep breath — you're okay right now.").strip()
