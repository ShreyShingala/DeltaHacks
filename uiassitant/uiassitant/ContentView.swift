import SwiftUI
import SmartSpectraSwiftSDK // ⚠️ Replace with actual import name if different

struct ContentView: View {
    @StateObject private var assistant = AudioAssistant()
    
    // Colors
    let calmSage = Color(red: 0.55, green: 0.65, blue: 0.55)
    let panicRed = Color(red: 0.85, green: 0.3, blue: 0.3)
    let activeBlue = Color(red: 0.3, green: 0.5, blue: 0.9)
    
    var body: some View {
        ZStack {
            // 1. PRESAGE CAMERA LAYER (The Eyes)
            // This runs the computer vision in the background
            SmartSpectraView()
                .opacity(0.4) // Make it semi-transparent (Sci-fi HUD look)
                .edgesIgnoringSafeArea(.all)
                .grayscale(1.0) // Make it black & white for "Medical Device" feel
            
            // 2. BACKGROUND OVERLAY
            (assistant.isSpeaking ? activeBlue : calmSage)
                .opacity(0.85) // See through to the camera slightly
                .edgesIgnoringSafeArea(.all)
                .animation(.easeInOut, value: assistant.isSpeaking)
            
            VStack(spacing: 30) {
                
                // TOP BAR
                HStack {
                    // Pulse the dot if High Stress is detected
                    Circle()
                        .fill(assistant.isHighStress ? Color.red : Color.green)
                        .frame(width: 12, height: 12)
                        .shadow(radius: 4)
                        .scaleEffect(assistant.isHighStress ? 1.5 : 1.0)
                        .animation(.easeInOut(duration: 0.5).repeatForever(), value: assistant.isHighStress)
                    
                    Text(assistant.isHighStress ? "STRESS DETECTED" : "Vitals Normal")
                        .foregroundColor(.white)
                        .font(.headline)
                        .bold()
                    Spacer()
                }
                .padding(.top, 50)
                .padding(.horizontal)
                
                Spacer()
                
                // LIVE DEBUG STATS (For the Judges!)
                HStack(spacing: 20) {
                    VStack {
                        Text("HEART RATE")
                            .font(.caption2)
                            .bold()
                        Text("\(Int(assistant.currentHeartRate)) BPM")
                            .font(.title3)
                            .monospacedDigit()
                    }
                    Divider().frame(height: 30)
                    VStack {
                        Text("FOCUS")
                            .font(.caption2)
                            .bold()
                        Text("\(Int(assistant.currentFocus * 100))%")
                            .font(.title3)
                            .monospacedDigit()
                    }
                }
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.4))
                .cornerRadius(10)
                
                // ... (Keep your Text Captions and Buttons here) ...
                
                Spacer()
                
                // PANIC BUTTON
                Button(action: {
                    assistant.sendToBackend(text: "I am confused and need help immediately.")
                }) {
                    Text("HELP ME")
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 90)
                        .background(panicRed)
                        .cornerRadius(20)
                        .shadow(radius: 10)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            // Start the sensors when the app loads
            assistant.startPresageMonitoring()
        }
    }
}
