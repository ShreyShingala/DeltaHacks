import Foundation
import Speech
import AVFoundation
import SwiftUI
import Combine
import SmartSpectraSwiftSDK

class AudioAssistant: NSObject, ObservableObject, AVAudioPlayerDelegate {
    // --- 🛠️ TEST MODE 🛠️ ---
    // TRUE  = Logs to /listennah (No Audio, Saves Credits)
    // FALSE = Sends to /listen (Real Audio response)
    private let useTestMode = true
    
    // --- UI VARIABLES ---
    @Published var spokenText = "Initializing..."
    @Published var isListening = false
    @Published var isSpeaking = false
    
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
    private var isProcessingRequest = false
    
    // --- MOVEMENT TRACKING ---
    private var lastFaceCentroid: CGPoint?
    private var lastInterventionTime: Date = Date.distantPast
    private var sessionStartTime: Date?
    
    // Config
    private let silenceThreshold: TimeInterval = 1.5
    private let serverIP = "192.168.0.164"
    
    override init() {
        super.init()
        
        // 1. Force Clean Start
        SmartSpectraVitalsProcessor.shared.stopProcessing()
        SmartSpectraVitalsProcessor.shared.stopRecording()
        
        // 2. NEW API KEY
        let apiKey = "NSphZrIStb8J6ZBtujZbaaeKe3sAe2AR5SZHtskh"
        SmartSpectraSwiftSDK.shared.setApiKey(apiKey)
        SmartSpectraSwiftSDK.shared.setSmartSpectraMode(.continuous)
        SmartSpectraSwiftSDK.shared.setCameraPosition(.front)
        
        configureAudioSession()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.startListeningSequence()
        }
    }
    
    deinit {
        stopPresageMonitoring()
        nukeAudio()
    }
    
    // --- LOUD AUDIO CONFIG ---
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
        if isMonitoring { return }
        isMonitoring = true
        sessionStartTime = Date()
        
        if SmartSpectraVitalsProcessor.shared.processingStatus != .processing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                SmartSpectraVitalsProcessor.shared.startProcessing()
                SmartSpectraVitalsProcessor.shared.startRecording()
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
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
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.processSensorData()
        }
    }
    
    // --- AUDIO LOGIC ---
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
        
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
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
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            print("🤫 Silence detected. Sending...")
            self?.sendDataToBackend()
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
        
        // --- TEST MODE ---
        if useTestMode {
            print("🟨 TEST MODE: Logging to /listennah")
            guard let logUrl = URL(string: "http://\(serverIP):8000/listennah") else {
                isProcessingRequest = false
                return
            }
            
            var request = URLRequest(url: logUrl)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            
            URLSession.shared.dataTask(with: request) { [weak self] _, _, _ in
                print("✅ Log Sent. Resetting...")
                DispatchQueue.main.async { self?.finishTurn() }
            }.resume()
            return
        }
        
        // --- PRODUCTION ---
        guard let url = URL(string: "http://\(serverIP):8000/listen") else {
            isProcessingRequest = false
            return
        }
        
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
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
                speakingTimer = Timer.scheduledTimer(withTimeInterval: duration + 1.0, repeats: false) { [weak self] _ in
                    print("⚠️ Watchdog Reset")
                    self?.finishTurn()
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
    
    // --- SAFE VITALS & MOVEMENT ---
    func processSensorData() {
        if !isMonitoring { return }
        
        if let start = sessionStartTime, Date().timeIntervalSince(start) < 5.0 { return }
        
        guard let metrics = SmartSpectraSwiftSDK.shared.metricsBuffer else { return }
        
        let hr = Double(metrics.pulse.rate.last?.value ?? 0.0)
        let br = Double(metrics.breathing.rate.last?.value ?? 0.0)
        
        var face = false
        var currentMovement = 0.0
        var isShakingViolently = false
        
        if let edge = SmartSpectraSwiftSDK.shared.edgeMetrics {
            face = edge.hasFace
            
            // Calculate Centroid
            if face, let landmarks = edge.face.landmarks.last?.value, !landmarks.isEmpty {
                var totalX: Float = 0, totalY: Float = 0
                let count = Double(landmarks.count)
                
                if count > 0 {
                    for point in landmarks { totalX += point.x; totalY += point.y }
                    let currentCentroid = CGPoint(x: Double(totalX)/count, y: Double(totalY)/count)
                    
                    if let last = lastFaceCentroid {
                        let dx = currentCentroid.x - last.x
                        let dy = currentCentroid.y - last.y
                        currentMovement = sqrt(dx*dx + dy*dy)
                        
                        // Shake Detection
                        if abs(dx) > 10.0 || abs(dy) > 10.0 {
                            isShakingViolently = true
                        }
                    }
                    lastFaceCentroid = currentCentroid
                }
            } else {
                lastFaceCentroid = nil
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Smoothed Movement
            self.movementScore = (self.movementScore * 0.8) + (currentMovement * 0.2)
            
            self.currentHeartRate = hr
            self.currentBreathingRate = br
            self.isFacePresent = face
            
            let isPanicking = (hr > 90.0)
            let isHyperventilating = (br > 20.0)
            let isAgitated = (self.movementScore > 5.0 || isShakingViolently)
            
            if isPanicking || isHyperventilating || isAgitated {
                self.isHighStress = true
                
                // Auto-Trigger (Every 30s)
                if !self.isProcessingRequest && Date().timeIntervalSince(self.lastInterventionTime) > 10.0 {
                    self.lastInterventionTime = Date()
                    
                    if isShakingViolently { self.triggerAutoIntervention(reason: "Violent Head Shaking") }
                    else if isAgitated { self.triggerAutoIntervention(reason: "Physical Agitation") }
                    else if isPanicking { self.triggerAutoIntervention(reason: "High Heart Rate") }
                    else { self.triggerAutoIntervention(reason: "Hyperventilation") }
                }
            } else {
                self.isHighStress = false
            }
        }
    }
}
