#!/usr/bin/env python3
"""Quick migration script - non-interactive version to add original_message.

This script automatically updates all events missing original_message field.
Use this if you want to run it without prompts (e.g., in scripts).
"""
import os
from dotenv import load_dotenv
from pymongo import MongoClient

try:
    load_dotenv()
except Exception:
    pass

MONGO_URI = os.getenv("MONGO_URI", "mongodb://localhost:27017")

try:
    client = MongoClient(MONGO_URI, tlsAllowInvalidCertificates=True)
    db = client.get_database("presage_db")
    events = db.get_collection("events")
    
    # Find all events missing original_message
    query = {"info.original_message": {"$exists": False}}
    events_to_update = list(events.find(query))
    
    print(f"Found {len(events_to_update)} events to update")
    
    updated = 0
    for event in events_to_update:
        info = event.get("info", {})
        raw = info.get("raw", "")
        
        result = events.update_one(
            {"_id": event.get("_id")},
            {"$set": {"info.original_message": raw if raw else ""}}
        )
        
        if result.modified_count > 0:
            updated += 1
    
    print(f"✅ Updated {updated} events")
    
    # Verify
    remaining = events.count_documents(query)
    print(f"Remaining without original_message: {remaining}")
    
except Exception as e:
    print(f"❌ Error: {e}")
    exit(1)

