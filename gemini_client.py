import os
import json
import re
import requests
import cohere
from dotenv import load_dotenv

load_dotenv()

# Configuration
USE_COHERE = os.getenv("USE_COHERE", "false").lower() == "true"
COHERE_API_KEY = os.getenv("COHERE_API_KEY")
COHERE_MODEL = "command-a-03-2025"  # Current available model

# Ollama configuration (fallback)
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "gemma:2b")

# Initialize Cohere client
cohere_client = None
if USE_COHERE and COHERE_API_KEY:
    cohere_client = cohere.Client(COHERE_API_KEY)
    print(f"✅ Cohere client initialized (model: {COHERE_MODEL})")
else:
    print(f"⚠️  Using Ollama fallback (USE_COHERE={USE_COHERE})")


def _call_cohere(prompt: str, max_tokens: int = 256, return_json: bool = False) -> str:
    """Call Cohere API. Returns text response.
    
    Args:
        prompt: The prompt to send to Cohere
        max_tokens: Maximum tokens in response
        return_json: If True, tries to extract JSON from response. If False, returns plain text.
    """
    try:
        if not cohere_client:
            return "Cohere client not initialized. Check your API key."
        
        response = cohere_client.chat(
            model=COHERE_MODEL,
            message=prompt,
            max_tokens=max_tokens,
            temperature=0.7,
        )
        
        text = response.text.strip()
        
        if return_json:
            # Try to extract JSON from the response
            json_match = re.search(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}', text, re.DOTALL)
            if json_match:
                try:
                    parsed = json.loads(json_match.group())
                    return json.dumps(parsed)
                except json.JSONDecodeError:
                    pass
        
        return text
        
    except Exception as e:
        print(f"❌ Cohere API error: {e}")
        if return_json:
            return json.dumps({"error": str(e), "raw": prompt})
        return "I encountered an error while processing your request. Please try again."


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


def _call_llm(prompt: str, max_tokens: int = 256, return_json: bool = False) -> str:
    """Unified LLM caller - routes to Cohere or Ollama based on USE_COHERE flag."""
    if USE_COHERE:
        return _call_cohere(prompt, max_tokens, return_json)
    else:
        return _call_ollama(prompt, max_tokens, return_json)


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
    
    text = _call_llm(prompt, max_tokens=300, return_json=True)

    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict):
            # If Ollama returned an error, don't return it - use fallback instead
            if "error" in parsed:
                return {
                    "raw": message,
                    "intent": "note"
                }
            # Success - return the parsed result, but always include raw field
            # Normalize schema: always include raw for consistency
            parsed["raw"] = message
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
    
    # Check if this is an ACTIVE stress alert (not just aftermath)
    # Stress mode should only activate for ALERT messages with vital signs
    is_alert_message = current_msg.upper().startswith("ALERT:")
    active_stress = stress_detected and is_alert_message
    
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
    
    # Build conversation history from last 5 messages
    history_messages = []
    for event in recent_events[:5]:  # Get last 5 messages
        info = event.get("info", {})
        raw_msg = info.get("raw") or info.get("notes") or info.get("original_message", "")
        if raw_msg:
            history_messages.append(raw_msg)
    
    history_str = "\n".join([f"- {msg}" for msg in history_messages]) if history_messages else ""
    
    # Debug logging
    print(f"📚 Past 5 messages:\n{history_str if history_str else 'None'}")
    
    # Adjust prompt based on ACTIVE stress/dementia episode detection
    if active_stress:
        # DEMENTIA EPISODE MODE - Focus on calming, grounding, orienting
        # Only use this for ACTIVE alerts, not follow-up questions
        prompt = (
            f"You are helping {user_name}, an elderly person with severe short-term and long-term memory loss who is experiencing a distressing dementia episode.\n\n"
            f"They said: \"{current_msg}\"\n"
            f"Their vitals show they are highly stressed and confused.\n"
        )
        
        if history_str:
            prompt += f"What you know: {history_str}\n"
        
        prompt += (
            "\nYour goal is to help them relax and calm down:\n"
            "- Use their name and speak slowly with a reassuring, gentle tone\n"
            "- Ground them in reality: remind them they're safe at home\n"
            "- If they're asking a question, answer it briefly while also reassuring them\n"
            "- Validate their feelings without arguing or correcting harshly\n"
            "- Help reduce their anxiety with simple, comforting words\n"
            "- Keep sentences very short and simple due to their memory impairment\n\n"
            "CRITICAL: Your response MUST be under 25 words total. Maximum 2 sentences.\n"
            "Your calming response:"
        )
    else:
        # NORMAL MODE - Friendly conversational
        prompt = (
            f"You are a caring companion speaking to {user_name}, an elderly person with short-term and long-term memory loss.\n\n"
            f"They just told you: \"{current_msg}\"\n"
            f"Current context: {context_str}\n"
        )
        
        if history_str:
            prompt += f"\nTHEIR RECENT CONVERSATION HISTORY (last 5 messages):\n{history_str}\n"
            prompt += "\n🚨 CRITICAL: If they're asking about something they said in recent history, answer with the SPECIFIC FACT from history. Don't guess or suggest - tell them what they actually said.\n"
        
        prompt += (
            "\nRespond warmly and helpfully:\n"
            "- Use their PREVIOUS INFORMATION to give specific factual answers, not guesses\n"
            "- If no previous information exists, then help them figure it out\n"
            "- Acknowledge what they shared with empathy\n"
            "- Natural, conversational speech only - no formatting\n\n"
            "CRITICAL: Your response MUST be under 30 words total. Maximum 2-3 short sentences.\n"
            "Your response:"
        )
    
    text = _call_llm(prompt, max_tokens=50, return_json=False)
    
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
