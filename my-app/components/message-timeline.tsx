"use client"

import { useEffect, useState } from "react"
import type { Message } from "@/types/message"
import { MessageCard } from "./message-card"
import { Loader2 } from "lucide-react"

interface MessageTimelineProps {
  patientId: string
}

export function MessageTimeline({ patientId }: MessageTimelineProps) {
  const [messages, setMessages] = useState<Message[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [refreshKey, setRefreshKey] = useState(0)

  const fetchMessages = async () => {
    try {
      setLoading(true)
      setError(null)
      const response = await fetch(`/api/messages?patientId=${patientId}`)
      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}))
        throw new Error(errorData.details || errorData.error || "Failed to fetch messages")
      }
      const data = await response.json()
      setMessages(data)
    } catch (err: any) {
      const errorMessage = err?.message || "Unable to load messages. Please try again."
      setError(errorMessage)
      console.error("[v0] Error:", err)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchMessages()
  }, [patientId, refreshKey])

  const handleUpdate = () => {
    fetchMessages() // Refresh after update
  }

  const handleDelete = () => {
    fetchMessages() // Refresh after delete
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="h-8 w-8 animate-spin text-primary" />
      </div>
    )
  }

  if (error) {
    return (
      <div className="text-center py-12">
        <p className="text-lg text-destructive">{error}</p>
      </div>
    )
  }

  if (messages.length === 0) {
    return (
      <div className="text-center py-12">
        <p className="text-lg text-muted-foreground">No messages yet</p>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      {messages.map((message) => (
        <MessageCard 
          key={message._id || Math.random()} 
          message={message}
          onUpdate={handleUpdate}
          onDelete={handleDelete}
        />
      ))}
    </div>
  )
}
