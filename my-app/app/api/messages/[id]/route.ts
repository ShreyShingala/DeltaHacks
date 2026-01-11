import { type NextRequest, NextResponse } from "next/server"
import clientPromise from "@/lib/mongodb"
import { ObjectId } from "mongodb"

// DELETE endpoint - Delete a message by ID
export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params

    if (!id) {
      return NextResponse.json({ error: "Message ID is required" }, { status: 400 })
    }

    const client = await clientPromise
    const db = client.db("presage_db")
    const eventsCollection = db.collection("events")

    // Delete the event by _id
    const result = await eventsCollection.deleteOne({ _id: new ObjectId(id) })

    if (result.deletedCount === 0) {
      return NextResponse.json({ error: "Message not found" }, { status: 404 })
    }

    console.log(`[API] Deleted message with ID: ${id}`)
    return NextResponse.json({ success: true, message: "Message deleted" })
  } catch (error: any) {
    console.error("[API] Error deleting message:", error)
    return NextResponse.json(
      { error: "Failed to delete message", details: error?.message },
      { status: 500 }
    )
  }
}

// PATCH endpoint - Update a message by ID
export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params
    const body = await request.json()
    const { content } = body

    if (!id) {
      return NextResponse.json({ error: "Message ID is required" }, { status: 400 })
    }

    if (!content) {
      return NextResponse.json({ error: "Content is required" }, { status: 400 })
    }

    const client = await clientPromise
    const db = client.db("presage_db")
    const eventsCollection = db.collection("events")

    // Get the existing event first
    const existingEvent = await eventsCollection.findOne({ _id: new ObjectId(id) })

    if (!existingEvent) {
      return NextResponse.json({ error: "Message not found" }, { status: 404 })
    }

    // Update the info.original_message and info.raw fields
    const updatedInfo = {
      ...existingEvent.info,
      original_message: content,
      raw: content,
    }

    // Update the event
    const result = await eventsCollection.updateOne(
      { _id: new ObjectId(id) },
      { $set: { info: updatedInfo } }
    )

    if (result.matchedCount === 0) {
      return NextResponse.json({ error: "Message not found" }, { status: 404 })
    }

    console.log(`[API] Updated message with ID: ${id}`)
    
    // Return the updated message
    const updatedEvent = await eventsCollection.findOne({ _id: new ObjectId(id) })
    const info = updatedEvent?.info || {}
    
    return NextResponse.json({
      _id: updatedEvent?._id?.toString(),
      content: content,
      timestamp: updatedEvent?.ts || new Date(),
      patientId: updatedEvent?.user,
      sender: "User",
      type: info.intent || "note",
    })
  } catch (error: any) {
    console.error("[API] Error updating message:", error)
    return NextResponse.json(
      { error: "Failed to update message", details: error?.message },
      { status: 500 }
    )
  }
}

