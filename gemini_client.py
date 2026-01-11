import os
import json
from dotenv import load_dotenv
import google.generativeai as genai

load_dotenv()

GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")
if GOOGLE_API_KEY:
    genai.configure(api_key=GOOGLE_API_KEY)


def _call_gemini(prompt: str, max_tokens: int = 256, return_json: bool = False) -> str:
    """Call Google Gemini using official SDK. Returns text response.
    If API key not configured, returns a fallback message.
    
    Args:
        prompt: The prompt to send to Gemini
        max_tokens: Maximum tokens in response
        return_json: If True, returns JSON string for structured data. If False, returns plain text.
    """
    if not GOOGLE_API_KEY:
        # Fallback for local dev without API key
        print("⚠️  WARNING: GOOGLE_API_KEY not set. Using fallback response.")
        if return_json:
            return json.dumps({"intent": "note", "raw": prompt})
        return "I'm having trouble connecting right now. Please try again in a moment."

    try:
        # Using gemini-1.5-flash for faster responses (or gemini-1.5-pro for better quality)
        model = genai.GenerativeModel('gemini-flash-latest')
        generation_config = genai.types.GenerationConfig(
            max_output_tokens=max_tokens,
            temperature=0.7,
        )
        response = model.generate_content(prompt, generation_config=generation_config)
        
        # Handle safety-filtered responses (finish_reason = 2 means SAFETY)
        if not response.candidates:
            error_msg = "Response was blocked - no candidates returned"
            print(f"⚠️  {error_msg}")
            if return_json:
                return json.dumps({"error": error_msg, "raw": prompt})
            return "I couldn't generate a response. Please try again."
        
        candidate = response.candidates[0]
        # finish_reason 2 = SAFETY (blocked by safety filters)
        if candidate.finish_reason == 2:
            error_msg = "Response was blocked by safety filters"
            print(f"⚠️  {error_msg} (finish_reason: {candidate.finish_reason})")
            if return_json:
                return json.dumps({"error": error_msg, "raw": prompt})
            return "I couldn't generate a response due to content filters. Please try again."
        
        # Check if content/parts exist before accessing response.text
        if not hasattr(candidate, 'content') or not candidate.content:
            error_msg = f"Response blocked - no content (finish_reason: {candidate.finish_reason})"
            print(f"⚠️  {error_msg}")
            if return_json:
                return json.dumps({"error": error_msg, "raw": prompt})
            return "I couldn't generate a response. Please try again."
        
        if not hasattr(candidate.content, 'parts') or not candidate.content.parts:
            error_msg = f"Response blocked - no parts (finish_reason: {candidate.finish_reason})"
            print(f"⚠️  {error_msg}")
            if return_json:
                return json.dumps({"error": error_msg, "raw": prompt})
            return "I couldn't generate a response. Please try again."
        
        # Get the text from the response (now safe to access)
        try:
            return response.text
        except ValueError as ve:
            # This can still happen in some edge cases
            error_msg = f"Could not extract text - finish_reason: {candidate.finish_reason}"
            print(f"⚠️  {error_msg}: {ve}")
            if return_json:
                return json.dumps({"error": error_msg, "raw": prompt})
            return "I couldn't extract the response text. Please try again."
    except Exception as e:
        print(f"❌ Gemini API error: {e}")
        if return_json:
            return json.dumps({"error": str(e), "raw": prompt})
        return f"I encountered an error while processing your request: {str(e)}"


def extract_important_info(message: str) -> dict:
    """Ask the model to extract important fields from a free-form message.

    Returns a dict with extracted fields when possible; always returns a dict.
    """
    prompt = (
        "Extract important information from the user's message and return valid JSON only. "
        "Return keys (when present): intent, entities, stress_level, location, time, notes. "
        f"User message: '''{message}'''"
    )
    text = _call_gemini(prompt, max_tokens=256, return_json=True)

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
    # Increased max_tokens to allow for longer, more helpful responses
    text = _call_gemini(prompt, max_tokens=512, return_json=False)
    return (text or "Take a deep breath — you're okay right now.").strip()
