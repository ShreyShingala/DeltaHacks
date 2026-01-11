#!/usr/bin/env python3
"""Simple script to check what's in MongoDB"""
import os
from db import get_context_for_user
from dotenv import load_dotenv
from pymongo import MongoClient
import json

try:
    load_dotenv()
except Exception:
    pass  # .env file might not exist or be accessible

MONGO_URI = os.getenv("MONGO_URI", "mongodb://localhost:27017")
DEFAULT_USER = os.getenv("PRESAGE_USER", "alice")

print(f"Connecting to MongoDB: {MONGO_URI}")
print(f"Database: presage_db")
print(f"Collection: events")
print(f"User: {DEFAULT_USER}")
print("=" * 60)

try:
    # Try to connect
    client = MongoClient(MONGO_URI)
    db = client.get_database("presage_db")
    events = db.get_collection("events")
    
    # Check total count
    total_count = events.count_documents({})
    print(f"\n📊 Total events in database: {total_count}")
    
    # Count by user
    users = events.distinct("user")
    print(f"👥 Users found: {users}")
    
    for user in users:
        user_count = events.count_documents({"user": user})
        print(f"   - {user}: {user_count} events")
    
    # Get recent events for default user
    if total_count > 0:
        print(f"\n📝 Recent events for user '{DEFAULT_USER}':")
        print("-" * 60)
        
        recent_events = get_context_for_user(DEFAULT_USER, limit=10)
        if recent_events:
            for i, event in enumerate(recent_events, 1):
                print(f"\n{i}. Event at {event.get('ts')}")
                print(f"   Info: {json.dumps(event.get('info', {}), indent=2)}")
        else:
            print(f"   No events found for user '{DEFAULT_USER}'")
            
        # Show all events (limit to last 5 for readability)
        print(f"\n🔍 All events (last 5):")
        print("-" * 60)
        all_events = list(events.find().sort("ts", -1).limit(5))
        for i, event in enumerate(all_events, 1):
            print(f"\n{i}. ID: {event.get('_id')}")
            print(f"   User: {event.get('user')}")
            print(f"   Timestamp: {event.get('ts')}")
            print(f"   Info: {json.dumps(event.get('info', {}), indent=2)}")
    else:
        print("\n❌ No events found in database!")
        print("   This could mean:")
        print("   - No data has been saved yet")
        print("   - MongoDB connection failed silently")
        print("   - Wrong database/collection name")
        
except Exception as e:
    print(f"\n❌ Error connecting to MongoDB: {e}")
    print("\nTroubleshooting:")
    print("1. Is MongoDB running? (check: mongosh or mongodb://localhost:27017)")
    print("2. Is MONGO_URI set correctly in .env file?")
    print("3. Are you using MongoDB Atlas? Check your connection string.")
