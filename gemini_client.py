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
    # Prompt optimized for elderly assistance - extract key information
    prompt = (
        "You are helping an elderly person. Extract key information from their message into JSON format.\n"
        "Fields to extract (if present):\n"
        "- intent: what they need (help, reminder, information, etc)\n"
        "- concern: any worry or problem mentioned\n"
        "- people: names of people mentioned\n"
        "- location: places mentioned (home, store, address, etc)\n"
        "- time: time or date references\n"
        "- items: objects they're looking for or need\n"
        "- emotion: how they seem to be feeling\n"
        "- notes: brief summary\n\n"
        f"Message: {message}\n\n"
        "Return only valid JSON."
    )
    text = _call_gemini(prompt, max_tokens=300, return_json=True)

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
    # Get current message and extracted info for context
    current_msg = context_info.get("current_message", "")
    extracted = context_info.get("extracted", {})
    recent_events = context_info.get("recent_events", [])
    stress_detected = context_info.get("stress_detected", False)
    vitals = context_info.get("vitals", {})
    
    # Build context summary from current extraction
    context_parts = []
    if extracted.get("concern"):
        context_parts.append(f"Concern: {extracted['concern']}")
    if extracted.get("items"):
        context_parts.append(f"Looking for: {extracted['items']}")
    if extracted.get("location"):
        context_parts.append(f"Location: {extracted['location']}")
    if extracted.get("people"):
        context_parts.append(f"People: {extracted['people']}")
    
    context_str = ", ".join(context_parts) if context_parts else "general request"
    
    # Build history summary from MongoDB - focus on key information
    history_summary = []
    for event in recent_events[:5]:  # Last 5 interactions
        info = event.get("info", {})
        raw_msg = info.get("raw", "")
        
        # Look for key-related information in past interactions
        if raw_msg:
            # Extract useful patterns from history
            if "found" in raw_msg.lower() and "key" in raw_msg.lower():
                history_summary.append(f"Previously: {raw_msg}")
            elif "put" in raw_msg.lower() and "key" in raw_msg.lower():
                history_summary.append(f"Previously: {raw_msg}")
    
    history_str = " ".join(history_summary[:3]) if history_summary else ""
    
    # Adjust prompt based on stress/dementia episode detection
    if stress_detected:
        # DEMENTIA EPISODE MODE - Focus on calming, grounding, orienting
        prompt = (
            f"You are a calming companion helping {user_name}, who is experiencing confusion or distress.\n\n"
            f"They said: \"{current_msg}\"\n"
            f"Vitals show elevated stress.\n"
        )
        
        if history_str:
            prompt += f"What you know: {history_str}\n"
        
        prompt += (
            "\nRespond with calming, grounding techniques:\n"
            "- Speak slowly and reassuringly\n"
            "- Help them orient: mention their name, where they are, that they're safe\n"
            "- If they want to go home but are home, gently remind them they're already home\n"
            "- Acknowledge their feelings without arguing\n"
            "- Use short, simple sentences\n"
            "- Keep it under 35 words\n"
            "- Natural calming speech only\n\n"
            "Your calming response:"
        )
    else:
        # NORMAL MODE - Friendly conversational
        prompt = (
            f"You are a caring companion speaking to {user_name}, an elderly friend.\n\n"
            f"They just told you: \"{current_msg}\"\n"
            f"Current context: {context_str}\n"
        )
        
        if history_str:
            prompt += f"What you know from before: {history_str}\n"
        
        prompt += (
            "\nRespond warmly and naturally:\n"
            "- Acknowledge what they shared\n"
            "- If they told you about family, show interest\n"
            "- If they need help finding something and history shows where it was, remind them\n"
            "- Keep it friendly and conversational, like talking to a good friend\n"
            "- Short sentences, under 40 words\n"
            "- Natural speech only - no formatting\n\n"
            "Your response:"
        )
    
    # Increased max_tokens to allow for longer, more helpful responses
    text = _call_gemini(prompt, max_tokens=200, return_json=False)
    
    # Better fallback if generation fails - make it context-aware
    if not text or "couldn't generate" in text.lower() or "content filter" in text.lower():
        # Create a conversational fallback based on what they said
        if "daughter" in current_msg.lower() or "son" in current_msg.lower() or "family" in current_msg.lower():
            return f"That's wonderful, {user_name}. Family is so important. Tell me more about them!"
        elif "key" in current_msg.lower() and "find" in current_msg.lower():
            return f"Let's find those keys together, {user_name}. Have you checked your usual spots?"
        elif "lost" in current_msg.lower() or "can't find" in current_msg.lower():
            return f"Don't worry, {user_name}. We'll figure this out together. Where did you last see it?"
        else:
            return f"I'm listening, {user_name}. How can I help you today?"
    
    # Clean up formatting for natural speech
    if text:
        # Remove markdown formatting
        text = re.sub(r'\*\*(.+?)\*\*', r'\1', text)  # Remove bold **text**
        text = re.sub(r'\*(.+?)\*', r'\1', text)      # Remove italic *text*
        text = re.sub(r'#+\s*', '', text)             # Remove headers
        text = re.sub(r'\n+', ' ', text)              # Replace newlines with spaces
        text = re.sub(r'\s+', ' ', text)              # Collapse multiple spaces
        text = re.sub(r'^\s*[-•]\s*', '', text)       # Remove bullet points
        text = text.strip()
        
        # Remove common AI response prefixes
        prefixes_to_remove = [
            "Here's what I'd say:",
            "I would say:",
            "Response:",
            "My response:",
        ]
        for prefix in prefixes_to_remove:
            if text.lower().startswith(prefix.lower()):
                text = text[len(prefix):].strip()
    
    return (text or f"I'm here to help you, {user_name}.").strip()
