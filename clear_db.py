#!/usr/bin/env python3
"""Script to clear all data from the events collection"""
from db import events, db
from pymongo import MongoClient

print("=" * 60)
print("Clearing database...")
print("=" * 60)

try:
    # Count documents before deletion
    count_before = events.count_documents({})
    print(f"\n📊 Current documents in events collection: {count_before}")
    
    if count_before == 0:
        print("✅ Database is already empty!")
    else:
        # Delete all documents
        result = events.delete_many({})
        print(f"\n🗑️  Deleted {result.deleted_count} documents")
        
        # Verify deletion
        count_after = events.count_documents({})
        print(f"📊 Remaining documents: {count_after}")
        
        if count_after == 0:
            print("✅ Database cleared successfully!")
        else:
            print(f"⚠️  Warning: {count_after} documents still remain")
            
except Exception as e:
    print(f"\n❌ Error clearing database: {e}")
    raise
