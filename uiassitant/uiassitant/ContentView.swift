import SwiftUI
import SmartSpectraSwiftSDK

struct ContentView: View {
    @StateObject private var assistant = AudioAssistant()
    @State private var isCameraActive = false
    
    // --- CALMING PALETTE ---
    let calmSage = Color(red: 0.55, green: 0.65, blue: 0.55)
    let panicRed = Color(red: 0.85, green: 0.3, blue: 0.3)
    let activeBlue = Color(red: 0.3, green: 0.5, blue: 0.9)
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                
                // ==========================================
                // TOP HALF: BIG CAMERA ACTIVATION BUTTON
                // ==========================================
                ZStack {
                    // Background
                    if isCameraActive {
                        // Show live camera feed
                        Color.black
                        
                        SmartSpectraView()
                            .opacity(0.6)
                            .grayscale(1.0)
                        
                        // Vitals Overlay (Only when camera active)
                        VStack {
                            // Status Badge
                            HStack {
                                Circle()
                                    .fill(assistant.isHighStress ? panicRed : Color.green)
                                    .frame(width: 8, height: 8)
                                    .shadow(radius: 4)
                                
                                Text(assistant.isFacePresent ? (assistant.isHighStress ? "DISTRESS DETECTED" : "VITALS STABLE") : "SEARCHING FOR FACE...")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.black.opacity(0.5))
                                    .cornerRadius(20)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                                
                                Spacer()
                            }
                            .padding(.top, 50)
                            .padding(.horizontal)
                            
                            Spacer()
                            
                            // Live Vitals Grid
                            if assistant.isFacePresent {
                                HStack(spacing: 12) {
                                    VitalsBox(icon: "heart.fill", label: "HR", value: "\(Int(assistant.currentHeartRate))", unit: "BPM", color: panicRed)
                                    VitalsBox(icon: "lungs.fill", label: "BR", value: "\(Int(assistant.currentBreathingRate))", unit: "/min", color: activeBlue)
                                    VitalsBox(icon: "person.fill.turn.right", label: "MVMT", value: "\(Int(assistant.movementScore))", unit: "", color: .orange)
                                }
                                .padding(.bottom, 20)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                    } else {
                        // Inactive state - Big "Tap to Start" button
                        LinearGradient(
                            gradient: Gradient(colors: [calmSage, calmSage.opacity(0.8)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        
                        VStack(spacing: 20) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.white)
                            
                            Text("TAP TO START\nVITAL MONITORING")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            
                            Text("Camera will activate to monitor\nheart rate, breathing, and movement")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .frame(height: geometry.size.height * 0.5)
                .contentShape(Rectangle()) // Make entire area tappable
                .onTapGesture {
                    if !isCameraActive {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isCameraActive = true
                        }
                        assistant.startPresageMonitoring()
                    }
                }
                
                // ==========================================
                // BOTTOM HALF: MICROPHONE & ASSISTANT
                // ==========================================
                ZStack {
                    // Background Color changes based on state
                    (assistant.isHighStress ? panicRed.opacity(0.9) : (assistant.isSpeaking ? activeBlue : calmSage))
                        .animation(.easeInOut(duration: 0.5), value: assistant.isHighStress)
                        .animation(.easeInOut(duration: 0.5), value: assistant.isSpeaking)
                    
                    VStack(spacing: 25) {
                        
                        // 1. Transcript / Message Box
                        ScrollView {
                            Text(assistant.spokenText)
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.top, 30)
                                .padding(.horizontal, 20)
                        }
                        .frame(height: 120)
                        
                        // 2. Server Status (Subtle)
                        Text(assistant.serverResponse)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                        
                        Spacer()
                        
                        // 3. Main Microphone Button
                        Button(action: {
                            if assistant.isListening {
                                assistant.stopListening(sendData: true)
                            } else {
                                assistant.startListening()
                            }
                        }) {
                            ZStack {
                                // Outer Ring Pulse
                                if assistant.isListening {
                                    Circle()
                                        .stroke(Color.white.opacity(0.5), lineWidth: 4)
                                        .frame(width: 85, height: 85)
                                        .scaleEffect(1.2)
                                        .opacity(0.0)
                                }
                                
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 80, height: 80)
                                    .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                                
                                Image(systemName: assistant.isListening ? "square.fill" : "mic.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(assistant.isListening ? panicRed : calmSage)
                            }
                        }
                        
                        // 4. Panic / Help Button
                        Button(action: {
                            assistant.sendToBackend(text: "I am confused and need help immediately.")
                        }) {
                            Text("HELP ME")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(assistant.isHighStress ? panicRed : calmSage)
                                .frame(maxWidth: .infinity)
                                .frame(height: 55)
                                .background(Color.white)
                                .cornerRadius(15)
                                .shadow(color: Color.black.opacity(0.1), radius: 5)
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 40)
                    }
                }
                .cornerRadius(30, corners: [.topLeft, .topRight])
                .offset(y: -25)
            }
        }
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}

// --- HELPER VIEWS ---

struct VitalsBox: View {
    let icon: String
    let label: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(width: 70, height: 60)
        .background(Color.black.opacity(0.6))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

// Rounded Corners Extension
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
