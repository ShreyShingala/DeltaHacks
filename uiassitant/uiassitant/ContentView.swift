import SwiftUI
import SmartSpectraSwiftSDK

struct ContentView: View {
    @StateObject private var assistant = AudioAssistant()
    @State private var isCameraActive = false
    
    // --- CALMING PALETTE ---
    let calmSage = Color(red: 0.55, green: 0.65, blue: 0.55)
    let panicRed = Color(red: 0.85, green: 0.3, blue: 0.3)
    let activeBlue = Color(red: 0.3, green: 0.5, blue: 0.9)
    let darkSlate = Color(red: 0.1, green: 0.12, blue: 0.15)
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                
                // ==========================================
                // TOP HALF: BIG CAMERA BUTTON
                // ==========================================
                ZStack {
                    // STATE 1: CAMERA ACTIVE (Scanning)
                    if isCameraActive {
                        ZStack {
                            // The Camera View
                            SmartSpectraView()
                                .opacity(1.0)
                                .grayscale(1.0)
                                .edgesIgnoringSafeArea(.top)
                            
                            // Vitals HUD Overlay
                            VStack {
                                HStack {
                                    Circle().fill(assistant.isHighStress ? panicRed : Color.green).frame(width: 10, height: 10).shadow(radius: 5)
                                    Text(assistant.isHighStress ? "DISTRESS DETECTED" : "VITALS MONITORING ACTIVE")
                                        .font(.caption).bold().foregroundColor(.white)
                                        .padding(8).background(Color.black.opacity(0.6)).cornerRadius(20)
                                    Spacer()
                                }
                                .padding(.top, 60).padding(.horizontal)
                                Spacer()
                                
                                // Live Vitals
                                if assistant.isFacePresent {
                                    HStack(spacing: 15) {
                                        VitalsBox(icon: "heart.fill", label: "HR", value: "\(Int(assistant.currentHeartRate))", color: panicRed)
                                        VitalsBox(icon: "lungs.fill", label: "BR", value: "\(Int(assistant.currentBreathingRate))", color: activeBlue)
                                        VitalsBox(icon: "person.fill.turn.right", label: "MVMT", value: "\(Int(assistant.movementScore))", color: .orange)
                                    }
                                    .padding(.bottom, 20)
                                }
                            }
                        }
                    }
                    // STATE 2: INACTIVE (Big "Tap to Start" Button)
                    else {
                        Button(action: {
                            withAnimation { isCameraActive = true }
                            // Start sensors immediately
                            assistant.startPresageMonitoring()
                        }) {
                            ZStack {
                                darkSlate.edgesIgnoringSafeArea(.top)
                                RoundedRectangle(cornerRadius: 30).stroke(Color.white.opacity(0.1), lineWidth: 2).padding(40)
                                VStack(spacing: 20) {
                                    Image(systemName: "faceid").font(.system(size: 60)).foregroundColor(calmSage)
                                    Text("TAP TO START\nVITALS SCAN").font(.headline).bold().multilineTextAlignment(.center).foregroundColor(.white)
                                    Text("(Automatically starts camera)").font(.caption).foregroundColor(.white.opacity(0.6))
                                }
                            }
                        }
                    }
                }
                .frame(height: geometry.size.height * 0.50)
                
                // ==========================================
                // BOTTOM HALF: MICROPHONE (Sage Green)
                // ==========================================
                ZStack {
                    // Background Color Reaction
                    (assistant.isHighStress ? panicRed.opacity(0.9) : (assistant.isSpeaking ? activeBlue : calmSage))
                        .edgesIgnoringSafeArea(.bottom)
                        .animation(.easeInOut(duration: 0.5), value: assistant.isHighStress)
                        .animation(.easeInOut(duration: 0.5), value: assistant.isSpeaking)
                    
                    VStack(spacing: 25) {
                        
                        // 1. Transcript
                        ScrollView {
                            Text(assistant.spokenText)
                                .font(.title2).fontWeight(.medium).foregroundColor(.white)
                                .multilineTextAlignment(.center).padding(.top, 40).padding(.horizontal, 20)
                        }
                        .frame(height: 120)
                        
                        // 2. Waveform Animation
                        if assistant.isListening {
                            HStack(spacing: 6) {
                                ForEach(0..<6) { _ in
                                    RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.8)).frame(width: 5, height: 40)
                                        .animation(.easeInOut(duration: 0.3).repeatForever().speed(Double.random(in: 0.8...1.5)), value: assistant.isListening)
                                }
                            }
                            .frame(height: 50)
                        } else {
                            Spacer().frame(height: 50)
                        }
                        
                        Spacer()
                        
                        // 3. Mic Button
                        Button(action: {
                            if assistant.isListening { assistant.stopListening(sendData: true) }
                            else { assistant.startListening() }
                        }) {
                            ZStack {
                                Circle().fill(Color.white).frame(width: 90, height: 90).shadow(radius: 10)
                                Image(systemName: assistant.isListening ? "square.fill" : "mic.fill")
                                    .font(.system(size: 35)).foregroundColor(assistant.isListening ? panicRed : calmSage)
                            }
                        }
                        
                        // 4. Emergency Button
                        Button(action: { assistant.sendToBackend(text: "I am confused. Help.") }) {
                            Text("EMERGENCY HELP").font(.caption).bold().foregroundColor(.white.opacity(0.7))
                                .padding(10).overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.3), lineWidth: 1))
                        }
                        .padding(.bottom, 40)
                    }
                }
                .cornerRadius(30, corners: [.topLeft, .topRight])
                .offset(y: -25)
            }
        }
        .edgesIgnoringSafeArea(.bottom)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

// --- HELPER VIEWS ---
struct VitalsBox: View {
    let icon: String; let label: String; let value: String; let color: Color
    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(color)
            Text(value).font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundColor(.white)
            Text(label).font(.system(size: 8, weight: .bold)).foregroundColor(.white.opacity(0.6))
        }
        .frame(width: 70, height: 60).background(Color.black.opacity(0.6)).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.15), lineWidth: 1))
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat; var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
