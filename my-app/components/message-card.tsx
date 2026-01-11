"use client"

import { useState } from "react"
import { Card } from "@/components/ui/card"
import type { Message } from "@/types/message"
import { Clock, Edit2, Trash2, X, Check } from "lucide-react"

interface MessageCardProps {
  message: Message
  onUpdate: () => void
  onDelete: () => void
}

export function MessageCard({ message, onUpdate, onDelete }: MessageCardProps) {
  const [isEditing, setIsEditing] = useState(false)
  const [editedContent, setEditedContent] = useState(message.content)
  const [isDeleting, setIsDeleting] = useState(false)
  const [isSaving, setIsSaving] = useState(false)

  const formatDate = (date: Date) => {
    const messageDate = new Date(date)
    const today = new Date()
    const yesterday = new Date(today)
    yesterday.setDate(yesterday.getDate() - 1)

    if (messageDate.toDateString() === today.toDateString()) {
      return `Today at ${messageDate.toLocaleTimeString("en-US", {
        hour: "numeric",
        minute: "2-digit",
      })}`
    } else if (messageDate.toDateString() === yesterday.toDateString()) {
      return `Yesterday at ${messageDate.toLocaleTimeString("en-US", {
        hour: "numeric",
        minute: "2-digit",
      })}`
    } else {
      return messageDate.toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
        year: "numeric",
        hour: "numeric",
        minute: "2-digit",
      })
    }
  }

  const getTypeColor = (type?: string, stressDetected?: boolean) => {
    // If stress is detected, use red background
    if (stressDetected) {
      return "bg-red-500/20 border-red-500/50"
    }
    
    switch (type) {
      case "reminder":
        return "bg-accent/10 border-accent"
      case "conversation":
        return "bg-primary/10 border-primary"
      default:
        return "bg-card border-border"
    }
  }

  const handleEdit = async () => {
    if (!message._id) return

    setIsSaving(true)
    try {
      const response = await fetch(`/api/messages/${message._id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ content: editedContent }),
      })

      if (!response.ok) {
        throw new Error("Failed to update message")
      }

      setIsEditing(false)
      onUpdate() // Refresh the list
    } catch (error) {
      console.error("Error updating message:", error)
      alert("Failed to update message. Please try again.")
    } finally {
      setIsSaving(false)
    }
  }

  const handleDelete = async () => {
    if (!message._id) return
    if (!confirm("Are you sure you want to delete this message?")) return

    setIsDeleting(true)
    try {
      const response = await fetch(`/api/messages/${message._id}`, {
        method: "DELETE",
      })

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}))
        throw new Error(errorData.error || "Failed to delete message")
      }

      // Success - refresh the list
      onDelete() // Refresh the list
    } catch (error) {
      console.error("Error deleting message:", error)
      alert(`Failed to delete message: ${error instanceof Error ? error.message : "Unknown error"}`)
    } finally {
      setIsDeleting(false)
    }
  }

  const extractedFields = message.extractedFields
  const hasExtractedFields = extractedFields && Object.keys(extractedFields).length > 0

  return (
    <Card className={`p-6 transition-all hover:shadow-md ${getTypeColor(message.type, message.stressDetected)}`}>
      <div className="flex flex-col gap-3">
        <div className="flex items-start justify-between gap-4">
          {isEditing ? (
            <textarea
              value={editedContent}
              onChange={(e) => setEditedContent(e.target.value)}
              className="flex-1 text-lg leading-relaxed text-foreground border rounded-md p-2 resize-none"
              rows={3}
              autoFocus
            />
          ) : (
            <div className="flex-1 space-y-2">
              <p className="text-lg leading-relaxed text-foreground">{message.content}</p>
              
              {/* Display extracted fields if available */}
              {hasExtractedFields && (
                <div className="mt-3 pt-3 border-t border-border/50">
                  <div className="flex flex-wrap gap-2 text-sm">
                    {extractedFields.concern && (
                      <span className="px-2 py-1 bg-accent/20 text-accent-foreground rounded-md">
                        <strong>Concern:</strong> {extractedFields.concern}
                      </span>
                    )}
                    {extractedFields.items && (
                      <span className="px-2 py-1 bg-primary/20 text-primary-foreground rounded-md">
                        <strong>Items:</strong> {extractedFields.items}
                      </span>
                    )}
                    {extractedFields.location && (
                      <span className="px-2 py-1 bg-blue-500/20 text-blue-700 dark:text-blue-300 rounded-md">
                        <strong>Location:</strong> {extractedFields.location}
                      </span>
                    )}
                    {extractedFields.people && (
                      <span className="px-2 py-1 bg-purple-500/20 text-purple-700 dark:text-purple-300 rounded-md">
                        <strong>People:</strong> {extractedFields.people}
                      </span>
                    )}
                    {extractedFields.time && (
                      <span className="px-2 py-1 bg-orange-500/20 text-orange-700 dark:text-orange-300 rounded-md">
                        <strong>Time:</strong> {extractedFields.time}
                      </span>
                    )}
                    {extractedFields.emotion && (
                      <span className="px-2 py-1 bg-pink-500/20 text-pink-700 dark:text-pink-300 rounded-md">
                        <strong>Emotion:</strong> {extractedFields.emotion}
                      </span>
                    )}
                    {extractedFields.notes && (
                      <span className="px-2 py-1 bg-gray-500/20 text-gray-700 dark:text-gray-300 rounded-md">
                        <strong>Notes:</strong> {extractedFields.notes}
                      </span>
                    )}
                  </div>
                </div>
              )}
            </div>
          )}
          
          {!isEditing && (
            <div className="flex gap-2">
              <button
                onClick={() => setIsEditing(true)}
                className="p-2 hover:bg-accent rounded-md transition-colors"
                title="Edit message"
              >
                <Edit2 className="h-4 w-4 text-muted-foreground hover:text-foreground" />
              </button>
              <button
                onClick={handleDelete}
                disabled={isDeleting}
                className="p-2 hover:bg-destructive/10 rounded-md transition-colors disabled:opacity-50"
                title="Delete message"
              >
                <Trash2 className="h-4 w-4 text-muted-foreground hover:text-destructive" />
              </button>
            </div>
          )}

          {isEditing && (
            <div className="flex gap-2">
              <button
                onClick={handleEdit}
                disabled={isSaving || editedContent.trim() === ""}
                className="p-2 hover:bg-primary/10 rounded-md transition-colors disabled:opacity-50"
                title="Save changes"
              >
                <Check className="h-4 w-4 text-primary" />
              </button>
              <button
                onClick={() => {
                  setIsEditing(false)
                  setEditedContent(message.content) // Reset to original
                }}
                disabled={isSaving}
                className="p-2 hover:bg-muted rounded-md transition-colors disabled:opacity-50"
                title="Cancel"
              >
                <X className="h-4 w-4 text-muted-foreground" />
              </button>
            </div>
          )}
        </div>
        <div className="flex items-center gap-2 text-muted-foreground">
          <Clock className="h-5 w-5" />
          <time className="text-base">{formatDate(message.timestamp)}</time>
          {message.sender && message.sender !== "System" && (
            <>
              <span className="text-muted-foreground/50">•</span>
              <span className="text-base">{message.sender}</span>
            </>
          )}
        </div>
      </div>
    </Card>
  )
}
