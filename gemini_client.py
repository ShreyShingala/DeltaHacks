import os
import json
import re
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
        response = model.generate_content(
            prompt, 
            generation_config=generation_config
        )
        
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
    # Very minimal prompt to avoid safety filter triggers
    prompt = f"Extract JSON: intent, entities, location, time, notes. Input: {message}"
    text = _call_gemini(prompt, max_tokens=256, return_json=True)

    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict):
            # If Gemini returned an error, don't return it - use fallback instead
            if "error" in parsed:
                # Gemini was blocked, return minimal structure instead
                return {
                    "raw": message,
                    "intent": "note"
                }
            # Success - return the parsed result
            return parsed
    except Exception:
        # JSON parsing failed, use fallback
        pass

    # Fallback: return minimal structure (safe, no error keys)
    return {
        "raw": message,
        "intent": "note"
    }


def generate_assistance(user_name: str, context_info: dict) -> str:
    """Produce a short, calm assistance message using context_info.

    The prompt is intentionally small: the app should later use a low-latency Gemini Flash model.
    """
    # Simplify context - only include essential info to avoid filter triggers
    context_clean = {
        "total_events": context_info.get("total_events", 0),
        "user": context_info.get("user", user_name)
    }
    
    # Very simple, neutral prompt
    prompt = (
        f"Write a brief, friendly message for {user_name}. "
        f"They have {context_clean['total_events']} logged interactions. "
        "Be warm and helpful. Keep it under 75 words."
    )
    
    # Increased max_tokens to allow for longer, more helpful responses
    text = _call_gemini(prompt, max_tokens=512, return_json=False)
    
    # Fallback if generation fails
    if not text or "couldn't generate" in text.lower() or "content filter" in text.lower():
        return f"Hello {user_name}! You have {context_clean['total_events']} logged interactions. How can I help you today?"
    
    # Clean up newlines - replace newlines with spaces, collapse multiple spaces
    if text:
        text = re.sub(r'\n+', ' ', text)  # Replace newlines with space
        text = re.sub(r'\s+', ' ', text)  # Replace multiple spaces with single space
        text = text.strip()
    
    return (text or f"Hello {user_name}! How can I help you today?").strip()
