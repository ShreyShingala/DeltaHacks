export interface Message {
  _id?: string
  content: string
  timestamp: Date
  patientId: string
  sender?: string
  type?: "reminder" | "note" | "conversation"
  originalMessage?: string
  stressDetected?: boolean
  extractedFields?: {
    concern?: string
    items?: string
    location?: string
    people?: string
    time?: string
    emotion?: string
    notes?: string
  }
}
