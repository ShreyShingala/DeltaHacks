import Foundation
import Speech
import AVFoundation
import SwiftUI
import Combine
import SmartSpectraSwiftSDK

class AudioAssistant: NSObject, ObservableObject, AVAudioPlayerDelegate {
    // --- UI VARIABLES ---
    @Published var spokenText = "Initializing..."
    @Published var isListening = false // Green (Your Turn)
    @Published var isSpeaking = false  // Blue (AI Turn)
    
    // --- VITALS VARIABLES ---
    @Published var currentHeartRate: Double = 0.0
    @Published var currentBreathingRate: Double = 0.0
    @Published var movementScore: Double = 0.0
    @Published var isHighStress: Bool = false
    @Published var isFacePresent: Bool = false
    
    // --- AUDIO COMPONENTS ---
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var audioPlayer: AVAudioPlayer?
    
    // --- STATE MANAGEMENT ---
    private var monitoringTimer: Timer?
    private var silenceTimer: Timer?
    private var speakingTimer: Timer?
    private var isMonitoring = false
    private var isProcessingRequest = false // Shield
    
    // --- MOVEMENT & TRIGGERS ---
    private var lastFaceCentroid: CGPoint?
    private var lastInterventionTime: Date = Date.distantPast // COOLDOWN
    private var sessionStartTime: Date? // WARM-UP TIMER
    
    // Config
    private let silenceThreshold: TimeInterval = 1.5
    private let serverIP = "172.17.79.245" // YOUR LAPTOP IP
    
    // --- INIT ---
    override init() {
        super.init()
        let apiKey = "QyQg2fsIqw3lSMXVvWIyv6Snt6kid0Dsabg4QHQA"
        SmartSpectraSwiftSDK.shared.setApiKey(apiKey)
        SmartSpectraSwiftSDK.shared.setSmartSpectraMode(.continuous)
        SmartSpectraSwiftSDK.shared.setCameraPosition(.front)
        
        configureAudioSession()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.startListeningSequence()
        }
    }
    
    // --- 1. LOUD AUDIO CONFIGURATION ---
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            try session.overrideOutputAudioPort(.speaker)
        } catch { print("❌ Session Error: \(error)") }
    }
    
    private func forceSpeaker() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.overrideOutputAudioPort(.none)
            try session.overrideOutputAudioPort(.speaker)
        } catch { print("🔊 Speaker Override Failed") }
    }
    
    // --- START / STOP ---
    func startPresageMonitoring() {
        isMonitoring = true
        sessionStartTime = Date() // START WARM-UP TIMER
        
        if SmartSpectraVitalsProcessor.shared.processingStatus == .processing {
            startVitalsLoop()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            SmartSpectraVitalsProcessor.shared.startProcessing()
            SmartSpectraVitalsProcessor.shared.startRecording()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.startVitalsLoop()
        }
    }
    
    func stopPresageMonitoring() {
        isMonitoring = false
        monitoringTimer?.invalidate()
        SmartSpectraVitalsProcessor.shared.stopProcessing()
        SmartSpectraVitalsProcessor.shared.stopRecording()
    }
    
    private func startVitalsLoop() {
        monitoringTimer?.invalidate()
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.processSensorData()
        }
    }
    
    // ==========================================
    //  AUDIO LOGIC
    // ==========================================
    
    func nukeAudio() {
        silenceTimer?.invalidate()
        speakingTimer?.invalidate()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        if let engine = audioEngine {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        
        if let player = audioPlayer {
            player.stop()
            player.delegate = nil
        }
        audioPlayer = nil
        
        DispatchQueue.main.async {
            self.isListening = false
            self.isSpeaking = false
        }
    }
    
    func startListeningSequence() {
        if isProcessingRequest { return }
        nukeAudio()
        
        DispatchQueue.main.async {
            self.isListening = true
            self.spokenText = "Listening..."
        }
        
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }
        
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        
        engine.prepare()
        do {
            try engine.start()
            forceSpeaker()
        } catch { print("❌ Engine Error: \(error)"); return }
        
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { result, error in
            if self.isProcessingRequest { return }
            if let result = result {
                DispatchQueue.main.async { self.spokenText = result.bestTranscription.formattedString }
                self.resetSilenceTimer()
            }
        }
    }
    
    private func resetSilenceTimer() {
        if isProcessingRequest { return }
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { _ in
            print("🤫 Silence detected. Sending...")
            self.sendDataToBackend()
        }
    }
    
    func sendDataToBackend() {
        isProcessingRequest = true
        let messageToSend = self.spokenText
        nukeAudio()
        
        if messageToSend.isEmpty || messageToSend == "Listening..." || messageToSend == "Speaking..." {
            isProcessingRequest = false
            startListeningSequence()
            return
        }
        
        sendPayload(text: messageToSend, isAutoTrigger: false)
    }
    
    func triggerAutoIntervention(reason: String) {
        isProcessingRequest = true
        nukeAudio()
        print("🚨 AUTO-TRIGGER: \(reason)")
        let systemMsg = "ALERT: User is silent but vital signs indicate \(reason). Initiate calming protocol immediately."
        sendPayload(text: systemMsg, isAutoTrigger: true)
    }
    
    func sendPayload(text: String, isAutoTrigger: Bool) {
        DispatchQueue.main.async {
            self.isSpeaking = true
            self.spokenText = isAutoTrigger ? "Sensing Distress..." : "Thinking..."
        }
        
        let payload: [String: Any] = [
            "text": text,
            "vitals": [
                "heart_rate": Int(self.currentHeartRate),
                "breathing_rate": Int(self.currentBreathingRate),
                "movement_score": Int(self.movementScore),
                "stress_detected": self.isHighStress
            ]
        ]
        
        guard let url = URL(string: "http://\(serverIP):8000/listen") else {
            isProcessingRequest = false
            return
        }
        
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if error != nil || data == nil || data?.first == 123 {
                DispatchQueue.main.async {
                    self.isProcessingRequest = false
                    self.startListeningSequence()
                }
                return
            }
            DispatchQueue.main.async { self.playAudio(data: data!) }
        }.resume()
    }
    
    func playAudio(data: Data) {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            forceSpeaker()
            
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.volume = 1.0
            audioPlayer?.prepareToPlay()
            
            let success = audioPlayer?.play() ?? false
            
            if success {
                DispatchQueue.main.async {
                    self.isSpeaking = true
                    self.spokenText = "Speaking..."
                }
                
                let duration = Double(audioPlayer?.duration ?? 2.0)
                speakingTimer?.invalidate()
                speakingTimer = Timer.scheduledTimer(withTimeInterval: duration + 1.0, repeats: false) { _ in
                    print("⚠️ Watchdog Reset")
                    self.finishTurn()
                }
            } else {
                finishTurn()
            }
        } catch {
            print("❌ Play Error: \(error)")
            finishTurn()
        }
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("✅ AI Finished.")
        finishTurn()
    }
    
    func finishTurn() {
        speakingTimer?.invalidate()
        isProcessingRequest = false
        startListeningSequence()
    }
    
    func triggerEmergency() {
        triggerAutoIntervention(reason: "User Requested Help")
    }
    
    // --- SAFE VITALS & WARM-UP LOGIC ---
    func processSensorData() {
        if !isMonitoring { return }
        
        // --- 1. WARM-UP CHECK (Prevents False Start) ---
        // If the session is less than 5 seconds old, ignore data.
        if let start = sessionStartTime, Date().timeIntervalSince(start) < 5.0 {
            // print("⏳ Warming up sensors...")
            return
        }
        
        guard let metrics = SmartSpectraSwiftSDK.shared.metricsBuffer else { return }
        
        let hr = Double(metrics.pulse.rate.last?.value ?? 0.0)
        let br = Double(metrics.breathing.rate.last?.value ?? 0.0)
        
        var face = false
        var currentMovement = 0.0
        
        if let edge = SmartSpectraSwiftSDK.shared.edgeMetrics {
            face = edge.hasFace
            if face, let landmarks = edge.face.landmarks.last?.value, !landmarks.isEmpty {
                var totalX: Float = 0, totalY: Float = 0
                for point in landmarks { totalX += point.x; totalY += point.y }
                let currentCentroid = CGPoint(x: Double(totalX)/Double(landmarks.count), y: Double(totalY)/Double(landmarks.count))
                
                if let last = lastFaceCentroid {
                    let dx = currentCentroid.x - last.x
                    let dy = currentCentroid.y - last.y
                    currentMovement = sqrt(dx*dx + dy*dy)
                }
                lastFaceCentroid = currentCentroid
            } else {
                lastFaceCentroid = nil
            }
        }
        
        DispatchQueue.main.async {
            self.movementScore = (self.movementScore * 0.9) + (currentMovement * 0.1)
            self.currentHeartRate = hr
            self.currentBreathingRate = br
            self.isFacePresent = face
            
            // --- TRIGGER LOGIC ---
            let isPanicking = (hr > 90.0)
            let isHyperventilating = (br > 20.0)
            let isAgitated = (self.movementScore > 5.0)
            
            if isPanicking || isHyperventilating || isAgitated {
                self.isHighStress = true
                
                if !self.isProcessingRequest && Date().timeIntervalSince(self.lastInterventionTime) > 10.0 {
                    self.lastInterventionTime = Date()
                    
                    if isPanicking { self.triggerAutoIntervention(reason: "High Heart Rate (Panic)") }
                    else if isHyperventilating { self.triggerAutoIntervention(reason: "Hyperventilation") }
                    else { self.triggerAutoIntervention(reason: "Physical Agitation") }
                }
            } else {
                self.isHighStress = false
            }
        }
    }
}
