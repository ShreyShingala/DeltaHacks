import Foundation
import Speech
import AVFoundation
import SwiftUI
import Combine
import SmartSpectraSwiftSDK //

class AudioAssistant: ObservableObject {
    // --- 1. AUDIO & SPEECH VARIABLES ---
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var audioPlayer: AVAudioPlayer?
    
    // --- 2. UI VARIABLES ---
    @Published var spokenText = "Press mic to speak..."
    @Published var isListening = false
    @Published var serverResponse = "Waiting for server..."
    @Published var isSpeaking = false
    
    // --- 3. PRESAGE / VITALS VARIABLES ---
    @Published var currentHeartRate: Double = 0.0
    @Published var currentBreathingRate: Double = 0.0
    @Published var movementScore: Double = 0.0
    @Published var isHighStress: Bool = false
    @Published var isFacePresent: Bool = false
    
    // Internal Logic
    private var monitoringTimer: Timer?
    private var lastInterventionTime: Date = Date.distantPast
    private var lastPresenceCheckTime: Date = Date.distantPast
    private var lastFaceCentroid: CGPoint?
    
    // --- 4. START MONITORING ---
    func startPresageMonitoring() {
        let apiKey = "QyQg2fsIqw3lSMXVvWIyv6Snt6kid0Dsabg4QHQA"
        
        // 1. Setup
        SmartSpectraSwiftSDK.shared.setApiKey(apiKey)
        SmartSpectraSwiftSDK.shared.setSmartSpectraMode(.continuous)
        SmartSpectraSwiftSDK.shared.setCameraPosition(.front)
        
        // 2. Bypass UI (Force Start)
        SmartSpectraSwiftSDK.shared.showControlsInScreeningView(false)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("⚡️ FORCE STARTING SENSORS...")
            SmartSpectraVitalsProcessor.shared.startProcessing()
            SmartSpectraVitalsProcessor.shared.startRecording()
        }
        
        print("✅ Presage Configured")
        
        // 3. Start Data Loop
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                self.processSensorData()
            }
        }
    }
    
    // --- 5. PROCESS SENSORS ---
    func processSensorData() {
        guard let metrics = SmartSpectraSwiftSDK.shared.metricsBuffer else { return }
        
        let heartRate = Double(metrics.pulse.rate.last?.value ?? 0.0)
        let breathingRate = Double(metrics.breathing.rate.last?.value ?? 0.0)
        
        var faceDetected = false
        var currentMovement = 0.0
        
        if let edgeMetrics = SmartSpectraSwiftSDK.shared.edgeMetrics {
            faceDetected = edgeMetrics.hasFace
            if let landmarks = edgeMetrics.face.landmarks.last?.value, !landmarks.isEmpty {
                var totalX: Float = 0, totalY: Float = 0
                for point in landmarks { totalX += point.x; totalY += point.y }
                let currentCentroid = CGPoint(x: Double(totalX)/Double(landmarks.count), y: Double(totalY)/Double(landmarks.count))
                
                if let last = lastFaceCentroid {
                    let dx = currentCentroid.x - last.x
                    let dy = currentCentroid.y - last.y
                    currentMovement = sqrt(dx*dx + dy*dy)
                }
                lastFaceCentroid = currentCentroid
            } else { lastFaceCentroid = nil }
        }
        
        // --- NEW: FACE LOSS CHECK ---
        if !faceDetected {
            // Check cooldown (only triggers every 10 seconds)
            if Date().timeIntervalSince(lastPresenceCheckTime) > 10.0 {
                lastPresenceCheckTime = Date()
                print("⚠️ Face lost - Calling /is-there")
                sendToPresenceCheck()
            }
        }
        // ----------------------------
        
        self.movementScore = (self.movementScore * 0.7) + (currentMovement * 0.3)
        
        DispatchQueue.main.async {
            self.currentHeartRate = heartRate
            self.currentBreathingRate = breathingRate
            self.isFacePresent = faceDetected
            
            let isPanicking = (heartRate > 100.0 && breathingRate > 20.0)
            let isAgitated = (self.movementScore > 15.0)
            
            if (isPanicking || isAgitated) {
                self.isHighStress = true
                self.triggerAutoHelp(reason: isPanicking ? "Panic" : "Agitation")
            } else {
                self.isHighStress = false
            }
        }
    }
    
    func triggerAutoHelp(reason: String) {
        if Date().timeIntervalSince(lastInterventionTime) < 30 { return }
        if isListening || isSpeaking { return }
        lastInterventionTime = Date()
        let msg = "System Alert: Distress detected (\(reason)). HR: \(Int(currentHeartRate)). Reassure user."
        sendToBackend(text: msg)
    }
    
    // --- 6. MICROPHONE LOGIC ---
    func startListening() {
        recognitionTask?.cancel(); recognitionTask = nil
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        try? audioEngine.start()
        
        DispatchQueue.main.async { self.isListening = true; self.spokenText = "Listening..." }
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                DispatchQueue.main.async { self.spokenText = result.bestTranscription.formattedString }
                if result.isFinal { self.stopListening(sendData: true) }
            }
            if error != nil { self.stopListening(sendData: false) }
        }
    }
    
    func stopListening(sendData: Bool) {
        if !isListening && !audioEngine.isRunning { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil; recognitionTask = nil
        DispatchQueue.main.async { self.isListening = false }
        if sendData && spokenText != "Listening..." { sendToBackend(text: self.spokenText) }
    }
    
    // --- 7. NETWORKING (STANDARD) ---
    func sendToBackend(text: String, isSilentLog: Bool = false) {
        let laptopIP = "172.17.79.245"
        guard let url = URL(string: "http://\(laptopIP):8000/listen") else { return }
        
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["text": text]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        if !isSilentLog { DispatchQueue.main.async { self.serverResponse = "Sending..." } }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { print("Net: \(error)"); return }
            if isSilentLog { return }
            guard let data = data else { return }
            
            if data.first != 123 { // Audio
                DispatchQueue.main.async { self.playAudio(data: data) }
            } else {
                DispatchQueue.main.async { self.serverResponse = "Logged." }
            }
        }.resume()
    }
    
    // --- 8. NETWORKING (PRESENCE CHECK) ---
    func sendToPresenceCheck() {
        // ENDPOINT: /is-there
        let laptopIP = "172.17.79.245"
        guard let url = URL(string: "http://\(laptopIP):8000/is-there") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // NO BODY ADDED (Matches your "takes no input" requirement)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { print("IsThere Error: \(error)"); return }
            guard let data = data else { return }
            
            // If the server returns audio, play it
            if !data.isEmpty && data.first != 123 {
                 DispatchQueue.main.async {
                    print("Playing Presence Check Audio")
                    self.playAudio(data: data)
                }
            }
        }.resume()
    }
    
    // --- 9. AUDIO PLAYER ---
    func playAudio(data: Data) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        audioPlayer = try? AVAudioPlayer(data: data)
        audioPlayer?.play()
        DispatchQueue.main.async { self.isSpeaking = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + (audioPlayer?.duration ?? 2)) {
            self.isSpeaking = false
            self.serverResponse = "Listening..."
        }
    }
}
