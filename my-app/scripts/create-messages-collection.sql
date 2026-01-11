-- MongoDB collection setup for messages
-- Run this in MongoDB shell or Compass

use memory_care;

db.createCollection("messages");

db.messages.createIndex({ "patientId": 1, "timestamp": -1 });

-- Sample data for testing
db.messages.insertMany([
  {
    content: "Remember to take your morning medication",
    patientId: "patient_001",
    sender: "Nurse Sarah",
    type: "reminder",
    timestamp: new Date()
  },
  {
    content: "Your family will visit at 2 PM today",
    patientId: "patient_001",
    sender: "Reception",
    type: "note",
    timestamp: new Date(Date.now() - 2 * 60 * 60 * 1000)
  },
  {
    content: "You had a great conversation with Dr. Johnson about your garden",
    patientId: "patient_001",
    sender: "Dr. Johnson",
    type: "conversation",
    timestamp: new Date(Date.now() - 24 * 60 * 60 * 1000)
  }
]);
