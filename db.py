import os
from datetime import datetime
from pymongo import MongoClient
from dotenv import load_dotenv

load_dotenv()  # Load environment variables from .env file

MONGO_URI = os.getenv("MONGO_URI", "mongodb://localhost:27017")
# Add tlsAllowInvalidCertificates for macOS SSL certificate issues
client = MongoClient(MONGO_URI, tlsAllowInvalidCertificates=True)
db = client.get_database("presage_db")
events = db.get_collection("events")

def save_event(user: str, info: dict) -> None:
    """Save an event to the database. Raises exception if write fails."""
    try:
        doc = {"user": user, "info": info, "ts": datetime.utcnow()}
        result = events.insert_one(doc)
        print(f"✅ Database write successful - ID: {result.inserted_id}")
        return result.inserted_id
    except Exception as e:
        print(f"❌ Database write failed: {e}")
        raise  # Re-raise so caller knows it failed

# def get_context_for_user(user: str, limit: int = 20) -> list:
#     cursor = events.find({"user": user}).sort("ts", -1).limit(limit)
#     out = []
#     for d in cursor:
#         dpop = {"info": d.get("info"), "ts": d.get("ts")}
#         out.append(dpop)
#     import os
#     from datetime import datetime
#     from dotenv import load_dotenv
#     from pymongo import MongoClient
#     from pymongo.server_api import ServerApi

#     load_dotenv()

#     # Use MONGO_URI from .env (recommended: mongodb+srv connection string)
#     MONGO_URI = os.getenv("MONGO_URI", "mongodb://localhost:27017")

#     # Create client with ServerApi(1) for modern Atlas clusters when using a connection string
#     try:
#         client = MongoClient(MONGO_URI, server_api=ServerApi('1'))
#         # ping to verify connection
#         try:
#             client.admin.command('ping')
#             print("Pinged your deployment. You successfully connected to MongoDB!")
#         except Exception as e:
#             print("Warning: could not ping MongoDB server:", e)
#     except Exception as e:
#         # Fallback to a simple client without ServerApi if the URI is local or invalid
#         print("MongoClient(ServerApi) creation failed, falling back to simple MongoClient:", e)
#         client = MongoClient(MONGO_URI)

#     db = client.get_database("presage_db")
#     events = db.get_collection("events")

def get_context_for_user(user: str, limit: int = 2000) -> list:
    """
    Return the most recent `limit` events for `user`, newest first.
    Assumes `events` is a valid pymongo Collection created elsewhere.
    """
    cursor = events.find({"user": user}).sort("ts", -1).limit(limit)

    out = []
    for d in cursor:
        out.append({
            "info": d.get("info"),
            "ts": d.get("ts"),
        })

    return out
