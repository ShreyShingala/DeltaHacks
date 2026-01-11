import { MessageTimeline } from "@/components/message-timeline"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"

export default function PatientDashboard() {
  // Using the actual user in the database
  const patientId = "shrey" // Actual user in database (PRESAGE_USER env is "shrey")

  return (
    <div className="min-h-screen bg-background">
      <div className="container mx-auto px-4 py-8 max-w-4xl">
        <header className="mb-8">
          <h1 className="text-4xl font-semibold text-foreground mb-2 text-balance">Your Messages</h1>
          <p className="text-xl text-muted-foreground leading-relaxed">
            Review your recent conversations and reminders
          </p>
        </header>

        <Card className="mb-6 border-2">
          <CardHeader className="pb-4">
            <CardTitle className="text-2xl">Message History</CardTitle>
            <CardDescription className="text-base">
              All your messages are displayed below with timestamps
            </CardDescription>
          </CardHeader>
          <CardContent>
            <MessageTimeline patientId={patientId} />
          </CardContent>
        </Card>

        <div className="text-center text-muted-foreground text-base">
          <p>Showing your most recent messages</p>
        </div>
      </div>
    </div>
  )
}
