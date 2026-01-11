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
                // TOP HALF: CAMERA (Unchanged)
                // ==========================================
                ZStack {
                    if isCameraActive {
                        ZStack {
                            SmartSpectraView()
                                .opacity(1.0)
                                .grayscale(1.0)
                                .edgesIgnoringSafeArea(.top)
                            
                            // HUD
                            VStack {
                                HStack {
                                    Circle()
                                        .fill(assistant.isHighStress ? panicRed : Color.green)
                                        .frame(width: 10, height: 10)
                                        .shadow(radius: 5)
                                    
                                    Text(assistant.isHighStress ? "DISTRESS DETECTED" : "VITALS MONITORING ACTIVE")
                                        .font(.caption).bold().foregroundColor(.white)
                                        .padding(8).background(Color.black.opacity(0.6)).cornerRadius(20)
                                    Spacer()
                                    
                                    // CLOSE BUTTON (X)
                                    Button(action: {
                                        withAnimation { isCameraActive = false }
                                        assistant.stopPresageMonitoring()
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                }
                                .padding(.top, 60).padding(.horizontal)
                                Spacer()
                                
                                if assistant.isFacePresent {
                                    HStack(spacing: 15) {
                                        VitalsBox(icon: "heart.fill", label: "HR", value: "\(Int(assistant.currentHeartRate))", unit: "BPM", color: panicRed)
                                        VitalsBox(icon: "lungs.fill", label: "BR", value: "\(Int(assistant.currentBreathingRate))", unit: "/min", color: activeBlue)
                                        VitalsBox(icon: "person.fill.turn.right", label: "MVMT", value: "\(Int(assistant.movementScore))", unit: "", color: .orange)
                                    }
                                    .padding(.bottom, 20)
                                }
                            }
                        }
                    } else {
                        // START BUTTON
                        Button(action: {
                            withAnimation { isCameraActive = true }
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
                .frame(height: geometry.size.height * 0.45)
                
                // ==========================================
                // BOTTOM HALF: ACCESSIBLE CONTROLS
                // ==========================================
                ZStack {
                    (assistant.isHighStress ? panicRed.opacity(0.9) : (assistant.isSpeaking ? activeBlue : calmSage))
                        .edgesIgnoringSafeArea(.bottom)
                        .animation(.easeInOut(duration: 0.5), value: assistant.isHighStress)
                    
                    VStack(spacing: 15) {
                        
                        // NEW SPACER: Pushes text down to the center
                        Spacer()
                        
                        // 1. Text Area (Auto-Scaling)
                        // Removed ScrollView -> Added minimumScaleFactor
                        Text(assistant.spokenText)
                            .font(.largeTitle) // Start with BIGGEST font
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .minimumScaleFactor(0.4) // Shrink down to 40% if text is too long
                            .frame(height: 120)      // Keep fixed height
                        
                        // SPACER: Keeps text pushed up from buttons
                        Spacer()
                        
                        // 2. LARGE RECTANGULAR MIC BUTTON
                        Button(action: {
                            if assistant.isListening {
                                assistant.stopListening(sendData: true)
                            } else {
                                assistant.startListening()
                            }
                        }) {
                            HStack(spacing: 20) {
                                Image(systemName: assistant.isListening ? "stop.fill" : "mic.fill")
                                    .font(.system(size: 40))
                                
                                Text(assistant.isListening ? "STOP LISTENING" : "TAP TO SPEAK")
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(assistant.isListening ? panicRed : calmSage)
                            .frame(maxWidth: .infinity)
                            .frame(height: 100)
                            .background(Color.white)
                            .cornerRadius(25)
                            .shadow(color: Color.black.opacity(0.15), radius: 8, y: 4)
                        }
                        .padding(.horizontal, 30)
                        
                        // 3. MASSIVE HELP BUTTON
                        Button(action: {
                            assistant.sendToBackend(text: "I am confused and need help immediately.")
                        }) {
                            VStack(spacing: 5) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title)
                                Text("HELP ME")
                                    .font(.system(size: 36, weight: .heavy))
                            }
                            .foregroundColor(assistant.isHighStress ? panicRed : calmSage)
                            .frame(maxWidth: .infinity)
                            .frame(height: 130)
                            .background(Color.white)
                            .cornerRadius(25)
                            .shadow(color: Color.black.opacity(0.15), radius: 8, y: 4)
                        }
                        .padding(.horizontal, 30)
                        .padding(.bottom, 30)
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
    let icon: String; let label: String; let value: String; let unit: String; let color: Color
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
