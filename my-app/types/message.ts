export interface Message {
  _id?: string
  content: string
  timestamp: Date
  patientId: string
  sender?: string
  type?: "reminder" | "note" | "conversation"
}
