#!/usr/bin/env python3
"""Migration script to add original_message field to existing MongoDB records.

This script updates existing events in the database to add the original_message field
if it's missing. It copies from 'raw' field if available, or uses the raw message as fallback.
"""
import os
from dotenv import load_dotenv
from pymongo import MongoClient

try:
    load_dotenv()
except Exception:
    pass  # .env file might not exist or be accessible

MONGO_URI = os.getenv("MONGO_URI", "mongodb://localhost:27017")
DEFAULT_USER = os.getenv("PRESAGE_USER", "alice")

print("=" * 60)
print("Migration: Adding original_message to existing events")
print("=" * 60)
print(f"Connecting to MongoDB: {MONGO_URI}")
print(f"Database: presage_db")
print(f"Collection: events")
print("=" * 60)
print()

try:
    # Connect to MongoDB
    client = MongoClient(MONGO_URI, tlsAllowInvalidCertificates=True)
    db = client.get_database("presage_db")
    events = db.get_collection("events")
    
    # Find all events that don't have original_message in info
    query = {
        "info.original_message": {"$exists": False}
    }
    
    events_to_update = list(events.find(query))
    total_count = len(events_to_update)
    
    print(f"📊 Found {total_count} events missing 'original_message' field")
    print()
    
    if total_count == 0:
        print("✅ No events need updating. All events already have 'original_message'!")
        exit(0)
    
    # Show a sample of what will be updated
    print("📝 Sample events to update (first 3):")
    print("-" * 60)
    for i, event in enumerate(events_to_update[:3], 1):
        info = event.get("info", {})
        raw = info.get("raw", "")
        
        # Debug: show all keys in info
        import json
        print(f"\n{i}. ID: {event.get('_id')}")
        print(f"   User: {event.get('user')}")
        print(f"   Info keys: {list(info.keys())}")
        print(f"   Has 'raw': {bool(raw)}")
        print(f"   Raw value: {repr(raw[:100]) if raw else 'N/A'}")
        
        # Check all possible fields that might contain the message
        if raw:
            print(f"   ✅ Will set original_message to: {raw[:50]}...")
        else:
            # Try to find the message in other fields
            notes = info.get("notes", "")
            items = info.get("items", "")
            concern = info.get("concern", "")
            print(f"   ⚠️  No 'raw' field found")
            print(f"   Notes: {notes[:50] if notes else 'N/A'}...")
            print(f"   Items: {items[:50] if items else 'N/A'}...")
            print(f"   Concern: {concern[:50] if concern else 'N/A'}...")
            print(f"   ⚠️  Will set original_message to empty string (no source found)")
    print()
    print("-" * 60)
    print()
    
    # Ask for confirmation
    response = input("Do you want to proceed with the migration? (yes/no): ")
    if response.lower() not in ['yes', 'y']:
        print("❌ Migration cancelled.")
        exit(0)
    
    print()
    print("🔄 Starting migration...")
    print()
    
    updated_count = 0
    skipped_count = 0
    
    # Update each event
    for event in events_to_update:
        event_id = event.get("_id")
        info = event.get("info", {})
        
        # Determine what to set as original_message
        # Priority: 1) raw field (if exists and non-empty), 2) notes field (as fallback), 3) empty string
        raw = info.get("raw", "")
        notes = info.get("notes", "")
        
        if raw:
            # Use raw field if it exists (this is the actual original message)
            original_message = raw
        elif notes:
            # Fallback: use notes field (not the original, but a summary)
            original_message = notes
        else:
            # No source available - leave empty
            original_message = ""
        
        # Update the document
        result = events.update_one(
            {"_id": event_id},
            {"$set": {"info.original_message": original_message}}
        )
        
        if result.modified_count > 0:
            updated_count += 1
            if updated_count % 10 == 0:
                print(f"   ✅ Updated {updated_count}/{total_count} events...")
        else:
            skipped_count += 1
    
    print()
    print("=" * 60)
    print("📊 Migration Summary")
    print("=" * 60)
    print(f"✅ Successfully updated: {updated_count} events")
    if skipped_count > 0:
        print(f"⚠️  Skipped (no changes needed): {skipped_count} events")
    print(f"📝 Total processed: {total_count} events")
    print()
    
    # Verify the update
    print("🔍 Verifying migration...")
    remaining = events.count_documents(query)
    if remaining == 0:
        print("✅ Verification successful! All events now have 'original_message' field.")
    else:
        print(f"⚠️  Warning: {remaining} events still missing 'original_message' field.")
        print("   This might be expected if some events have no 'raw' field to copy from.")
    
    print()
    print("=" * 60)
    print("✅ Migration complete!")
    print("=" * 60)
    
except Exception as e:
    print(f"\n❌ Error during migration: {e}")
    print("\nTroubleshooting:")
    print("1. Is MongoDB running? (check: mongosh or mongodb://localhost:27017)")
    print("2. Is MONGO_URI set correctly in .env file?")
    print("3. Are you using MongoDB Atlas? Check your connection string.")
    exit(1)

