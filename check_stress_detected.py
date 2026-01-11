#!/usr/bin/env python3
"""Check for stress_detected field in MongoDB events"""
import os
from dotenv import load_dotenv
from pymongo import MongoClient
import json

load_dotenv()

MONGO_URI = os.getenv("MONGO_URI", "mongodb://localhost:27017")
DEFAULT_USER = os.getenv("PRESAGE_USER", "shrey")

print(f"Connecting to MongoDB: {MONGO_URI}")
print(f"Database: presage_db")
print(f"Collection: events")
print(f"User: {DEFAULT_USER}")
print("=" * 60)

try:
    client = MongoClient(MONGO_URI, tlsAllowInvalidCertificates=True)
    db = client.db("presage_db")
    events = db.collection("events")
    
    # Count total events
    total_count = events.count_documents({})
    print(f"\n📊 Total events in database: {total_count}")
    
    # Count events with stress_detected field
    stress_detected_count = events.count_documents({"info.stress_detected": True})
    stress_not_detected_count = events.count_documents({"info.stress_detected": False})
    stress_missing_count = events.count_documents({"info.stress_detected": {"$exists": False}})
    
    print(f"\n🔴 Events with stress_detected: true: {stress_detected_count}")
    print(f"🟢 Events with stress_detected: false: {stress_not_detected_count}")
    print(f"⚪ Events without stress_detected field: {stress_missing_count}")
    
    # Show recent events with stress_detected
    if stress_detected_count > 0:
        print(f"\n📝 Recent events with stress_detected: true:")
        print("-" * 60)
        stress_events = list(events.find({"info.stress_detected": True}).sort("ts", -1).limit(5))
        for i, event in enumerate(stress_events, 1):
            info = event.get("info", {})
            print(f"\n{i}. ID: {event.get('_id')}")
            print(f"   User: {event.get('user')}")
            print(f"   Timestamp: {event.get('ts')}")
            print(f"   Message: {info.get('original_message') or info.get('raw', 'N/A')}")
            print(f"   stress_detected: {info.get('stress_detected')}")
            print(f"   Intent: {info.get('intent', 'N/A')}")
            if info.get('concern'):
                print(f"   Concern: {info.get('concern')}")
    
    # Show structure of a recent event for verification
    print(f"\n📋 Sample event structure (most recent):")
    print("-" * 60)
    recent_event = events.find_one(sort=[("ts", -1)])
    if recent_event:
        info = recent_event.get("info", {})
        print(f"User: {recent_event.get('user')}")
        print(f"Timestamp: {recent_event.get('ts')}")
        print(f"Info keys: {list(info.keys())}")
        print(f"Has stress_detected: {'stress_detected' in info}")
        if 'stress_detected' in info:
            print(f"stress_detected value: {info.get('stress_detected')} (type: {type(info.get('stress_detected')).__name__})")
        print(f"\nFull info structure:")
        print(json.dumps(info, indent=2, default=str))
    
except Exception as e:
    print(f"\n❌ Error: {e}")
    import traceback
    traceback.print_exc()

