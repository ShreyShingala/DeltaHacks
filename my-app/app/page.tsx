import { MessageTimeline } from "@/components/message-timeline"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import Image from "next/image"
import corner_logo from "@/images/corner_logo.png"

const CornerLogo = () => {
  return (
    <div className="absolute top-0 left-0 z-0 p-0">
      <Image src={corner_logo} alt="Corner Logo" width={180} height={180} className="object-contain" />
    </div>
  )
}

export default function PatientDashboard() {
  // Using the actual user in the database
  const patientId = "shrey" // Actual user in database (PRESAGE_USER env is "shrey")

  return (
    <div className="min-h-screen bg-background relative">
      <CornerLogo />
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
