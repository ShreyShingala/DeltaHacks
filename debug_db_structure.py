#!/usr/bin/env python3
"""Debug script to see what fields exist in MongoDB events"""
import os
from dotenv import load_dotenv
from pymongo import MongoClient
import json

try:
    load_dotenv()
except Exception:
    pass

MONGO_URI = os.getenv("MONGO_URI", "mongodb://localhost:27017")
DEFAULT_USER = os.getenv("PRESAGE_USER", "alice")

try:
    client = MongoClient(MONGO_URI, tlsAllowInvalidCertificates=True)
    db = client.get_database("presage_db")
    events = db.get_collection("events")
    
    # Find events missing original_message
    query = {"info.original_message": {"$exists": False}}
    events_to_check = list(events.find(query).limit(10))
    
    print(f"Checking {len(events_to_check)} events missing original_message:")
    print("=" * 60)
    
    for i, event in enumerate(events_to_check, 1):
        info = event.get("info", {})
        print(f"\n{i}. Event ID: {event.get('_id')}")
        print(f"   User: {event.get('user')}")
        print(f"   Info keys: {list(info.keys())}")
        print(f"   Has 'raw': {'raw' in info}")
        if 'raw' in info:
            raw_value = info.get("raw", "")
            print(f"   'raw' value: {repr(raw_value)}")
            print(f"   'raw' length: {len(raw_value)}")
        else:
            print(f"   ⚠️  No 'raw' field found")
        
        # Show all fields
        print(f"   All fields:")
        for key, value in info.items():
            if isinstance(value, str):
                print(f"      - {key}: {repr(value[:50])}...")
            else:
                print(f"      - {key}: {value}")
    
    print("\n" + "=" * 60)
    print("Summary:")
    print(f"Total events checked: {len(events_to_check)}")
    has_raw = sum(1 for e in events_to_check if 'raw' in e.get('info', {}))
    print(f"Events with 'raw' field: {has_raw}")
    print(f"Events without 'raw' field: {len(events_to_check) - has_raw}")
    
except Exception as e:
    print(f"❌ Error: {e}")
    import traceback
    traceback.print_exc()

