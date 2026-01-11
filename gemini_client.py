import os
import json
import re
import requests
from dotenv import load_dotenv

load_dotenv()

# Ollama configuration
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "gemma:instruct")  # Default model, can be changed in .env


def _call_ollama(prompt: str, max_tokens: int = 256, return_json: bool = False) -> str:
    """Call local Ollama server. Returns text response.
    
    Args:
        prompt: The prompt to send to Ollama
        max_tokens: Maximum tokens in response
        return_json: If True, tries to extract JSON from response. If False, returns plain text.
    """
    try:
        url = f"{OLLAMA_BASE_URL}/api/generate"
        
        payload = {
            "model": OLLAMA_MODEL,
            "prompt": prompt,
            "stream": False,
            "options": {
                "num_predict": max_tokens,
                "temperature": 0.7,
            }
        }
        
        response = requests.post(url, json=payload, timeout=60)
        
        if response.status_code != 200:
            error_msg = f"Ollama API error: {response.status_code} - {response.text}"
            print(f"❌ {error_msg}")
            if return_json:
                return json.dumps({"error": error_msg, "raw": prompt})
            return "I'm having trouble connecting right now. Please try again in a moment."
        
        result = response.json()
        
        if "response" not in result:
            error_msg = "Ollama response missing 'response' field"
            print(f"⚠️  {error_msg}")
            if return_json:
                return json.dumps({"error": error_msg, "raw": prompt})
            return "I couldn't generate a response. Please try again."
        
        text = result["response"].strip()
        
        if return_json:
            # Try to extract JSON from the response
            # Look for JSON object in the text
            json_match = re.search(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}', text, re.DOTALL)
            if json_match:
                try:
                    parsed = json.loads(json_match.group())
                    return json.dumps(parsed)
                except json.JSONDecodeError:
                    pass
        
        return text
        
    except requests.exceptions.ConnectionError:
        error_msg = "Cannot connect to Ollama server. Is it running?"
        print(f"❌ {error_msg}")
        print(f"💡 Make sure Ollama is running: ollama serve")
        print(f"💡 Or check OLLAMA_BASE_URL in .env (current: {OLLAMA_BASE_URL})")
        if return_json:
            return json.dumps({"error": error_msg, "raw": prompt})
        return "I'm having trouble connecting right now. Please try again in a moment."
    except requests.exceptions.Timeout:
        error_msg = "Ollama request timed out"
        print(f"❌ {error_msg}")
        if return_json:
            return json.dumps({"error": error_msg, "raw": prompt})
        return "The request took too long. Please try again."
    except Exception as e:
        print(f"❌ Ollama API error: {e}")
        if return_json:
            return json.dumps({"error": str(e), "raw": prompt})
        return f"I encountered an error while processing your request: {str(e)}"


def extract_important_info(message: str) -> dict:
    """Ask the model to extract important fields from a free-form message.

    Returns a dict with extracted fields when possible; always returns a dict.
    """
    prompt = (
        "Extract key information from this message into JSON format.\n"
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
        "Return ONLY valid JSON, no other text."
    )
    
    text = _call_ollama(prompt, max_tokens=300, return_json=True)

    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict):
            # If Ollama returned an error, don't return it - use fallback instead
            if "error" in parsed:
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

    The prompt is intentionally small: the app should later use a low-latency model.
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
    
    text = _call_ollama(prompt, max_tokens=200, return_json=False)
    
    # Better fallback if generation fails - make it context-aware
    if not text or "error" in text.lower() or "couldn't" in text.lower():
        # Create a conversational fallback based on what they said
        if "daughter" in current_msg.lower() or "son" in current_msg.lower() or "family" in current_msg.lower():
            return f"That's wonderful, {user_name}. Family is so important. Tell me more about them!"
        elif "key" in current_msg.lower() and ("find" in current_msg.lower() or "lost" in current_msg.lower() or "where" in current_msg.lower()):
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
            "As a",
            "As an",
        ]
        for prefix in prefixes_to_remove:
            if text.lower().startswith(prefix.lower()):
                text = text[len(prefix):].strip()
    
    return (text or f"I'm here to help you, {user_name}.").strip()
