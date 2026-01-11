import { type NextRequest, NextResponse } from "next/server"
import clientPromise from "@/lib/mongodb"

const BOOL_DEBUG = false;

export async function GET(request: NextRequest) {
  try {
    const searchParams = request.nextUrl.searchParams
    const user = searchParams.get("user") || searchParams.get("patientId") || "shrey" // Default to "shrey" - actual user in database

    const client = await clientPromise
    const db = client.db("presage_db") // Use the same database as Python backend
    const eventsCollection = db.collection("events")
    
    // Query events for this user
    const events = await eventsCollection
      .find({ user })
      .sort({ ts: -1 }) // Sort by timestamp descending
      .limit(50)
      .toArray()

    console.log(`[API] Querying user: ${user}, Found ${events.length} events`)

    // Map events to message format for frontend
    const messages = events.map((event: any) => {
      const info = event.info || {}
      const originalMessage = info.raw || ""
      const content = originalMessage || JSON.stringify(info)
      
      if (BOOL_DEBUG) {
        return {
          _id: event._id?.toString(),
          content: content,
          timestamp: event.ts || new Date(),
          patientId: event.user || user,
          sender: "User",
          type: info.intent || "note",
          originalData: info, // Include full info for debugging
        }
      } else {
        return {
          timestamp: event.ts || new Date(),
          sender: "User",
          content: originalMessage,
        }
      }
    })

    return NextResponse.json(messages)
  } catch (error: any) {
    console.error("[API] Error fetching messages:", error)
    const errorMessage = error?.message || "Unknown error"
    console.error("[API] Error details:", errorMessage)
    return NextResponse.json(
      { 
        error: "Failed to fetch messages", 
        details: errorMessage 
      }, 
      { status: 500 }
    )
  }
}

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    const { content, patientId, sender, type } = body

    if (!content || !patientId) {
      return NextResponse.json({ error: "Content and Patient ID are required" }, { status: 400 })
    }

    const client = await clientPromise
    const db = client.db("memory_care")

    const message = {
      content,
      patientId,
      sender: sender || "System",
      type: type || "note",
      timestamp: new Date(),
    }

    const result = await db.collection("messages").insertOne(message)

    return NextResponse.json({ ...message, _id: result.insertedId })
  } catch (error) {
    console.error("[v0] Error creating message:", error)
    return NextResponse.json({ error: "Failed to create message" }, { status: 500 })
  }
}
