#!/usr/bin/env python3
"""Quick test to verify Ollama connection and model availability"""
import requests
import os
from dotenv import load_dotenv

load_dotenv()

OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.2")

print("=" * 60)
print("Testing Ollama Connection")
print("=" * 60)
print(f"Base URL: {OLLAMA_BASE_URL}")
print(f"Model: {OLLAMA_MODEL}")
print()

# Test 1: Check if Ollama is running
print("1. Testing Ollama server connection...")
try:
    response = requests.get(f"{OLLAMA_BASE_URL}/api/tags", timeout=5)
    if response.status_code == 200:
        print("   ✅ Ollama server is running")
    else:
        print(f"   ❌ Unexpected status code: {response.status_code}")
        exit(1)
except requests.exceptions.ConnectionError:
    print("   ❌ Cannot connect to Ollama server")
    print(f"   💡 Make sure Ollama is running: ollama serve")
    exit(1)
except Exception as e:
    print(f"   ❌ Error: {e}")
    exit(1)

# Test 2: Check available models
print("\n2. Checking available models...")
try:
    response = requests.get(f"{OLLAMA_BASE_URL}/api/tags", timeout=5)
    models = response.json().get("models", [])
    model_names = [m.get("name", "") for m in models]
    
    if model_names:
        print(f"   ✅ Found {len(model_names)} model(s):")
        for name in model_names:
            print(f"      - {name}")
    else:
        print("   ⚠️  No models found")
        print(f"   💡 Pull a model: ollama pull {OLLAMA_MODEL}")
    
    # Check if configured model is available
    if model_names:
        if OLLAMA_MODEL in model_names or any(OLLAMA_MODEL in name for name in model_names):
            print(f"\n   ✅ Model '{OLLAMA_MODEL}' is available")
        else:
            print(f"\n   ⚠️  Model '{OLLAMA_MODEL}' not found in available models")
            print(f"   💡 Pull it with: ollama pull {OLLAMA_MODEL}")
            if model_names:
                print(f"   💡 Or use one of: {', '.join(model_names[:3])}")
    
except Exception as e:
    print(f"   ❌ Error checking models: {e}")

# Test 3: Try a simple generation
print(f"\n3. Testing generation with model '{OLLAMA_MODEL}'...")
try:
    payload = {
        "model": OLLAMA_MODEL,
        "prompt": "Say hello in one word.",
        "stream": False,
    }
    response = requests.post(f"{OLLAMA_BASE_URL}/api/generate", json=payload, timeout=30)
    
    if response.status_code == 200:
        result = response.json()
        if "response" in result:
            print(f"   ✅ Generation successful!")
            print(f"   Response: {result['response'].strip()[:100]}")
        else:
            print(f"   ⚠️  Unexpected response format: {result}")
    elif response.status_code == 404:
        print(f"   ❌ Model '{OLLAMA_MODEL}' not found")
        print(f"   💡 Pull it with: ollama pull {OLLAMA_MODEL}")
    else:
        print(f"   ❌ Generation failed: {response.status_code}")
        print(f"   Response: {response.text[:200]}")
except requests.exceptions.Timeout:
    print("   ⚠️  Request timed out (this is normal for first request)")
except Exception as e:
    print(f"   ❌ Error: {e}")

print("\n" + "=" * 60)
print("Test complete!")
print("=" * 60)

