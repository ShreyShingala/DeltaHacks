import Foundation
import Speech
import AVFoundation
import SwiftUI
import Combine
import SmartSpectraSwiftSDK

// Inherit from NSObject for Audio Delegate
class AudioAssistant: NSObject, ObservableObject, AVAudioPlayerDelegate {
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
    private var isMonitoring = false
    private var lastInterventionTime: Date = Date.distantPast
    private var lastPresenceCheckTime: Date = Date.distantPast
    private var lastFaceCentroid: CGPoint?
    
    // Conversation Logic
    private var faceLossAlertCount: Int = 0
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 1.5 // Wait 1.5s of silence before sending
    
    // --- INIT ---
    override init() {
        super.init()
        let apiKey = "QyQg2fsIqw3lSMXVvWIyv6Snt6kid0Dsabg4QHQA"
        print("🔑 Setting API Key...")
        SmartSpectraSwiftSDK.shared.setApiKey(apiKey)
        SmartSpectraSwiftSDK.shared.setSmartSpectraMode(.continuous)
        SmartSpectraSwiftSDK.shared.setCameraPosition(.front)
    }
    
    // --- 4. START MONITORING ---
    func startPresageMonitoring() {
        isMonitoring = true
        faceLossAlertCount = 0
        
        // Prevent SIGABRT: If already processing, just resume the data loop
        if SmartSpectraVitalsProcessor.shared.processingStatus == .processing {
            startDataLoop()
            // Auto-start listening if we aren't already
            if !isListening && !isSpeaking { startListening() }
            return
        }
        
        stopPresageMonitoring() // Safety Reset
        isMonitoring = true
        
        print("⏳ Waiting for Camera Initialization (3s)...")
        
        // Wait for Auth to finish
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if self.isMonitoring && SmartSpectraVitalsProcessor.shared.processingStatus != .processing {
                print("⚡️ ATTEMPTING FORCE START...")
                SmartSpectraVitalsProcessor.shared.startProcessing()
                SmartSpectraVitalsProcessor.shared.startRecording()
            }
        }
        
        // Start Data & Audio Loops
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            if self.isMonitoring {
                self.startDataLoop()
                self.startListening() // Start the Conversation Loop
            }
        }
    }
    
    func startDataLoop() {
        monitoringTimer?.invalidate()
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.processSensorData()
        }
    }
    
    func stopPresageMonitoring() {
        print("🛑 STOPPING ALL")
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        stopListening(sendData: false) // Kill mic
        audioPlayer?.stop() // Kill audio
        
        if SmartSpectraVitalsProcessor.shared.processingStatus == .processing {
            SmartSpectraVitalsProcessor.shared.stopProcessing()
            SmartSpectraVitalsProcessor.shared.stopRecording()
        }
    }
    
    // --- 5. PROCESS SENSORS ---
    func processSensorData() {
        if !isMonitoring { return }
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
        
        // --- FACE LOSS CHECK (LIMITED TO 2 TIMES) ---
        if !faceDetected {
            if isMonitoring &&
                Date().timeIntervalSince(lastPresenceCheckTime) > 10.0 &&
                !isSpeaking &&
                faceLossAlertCount < 2 {
                
                lastPresenceCheckTime = Date()
                faceLossAlertCount += 1
                
                print("⚠️ Face lost - Calling /is-there (Attempt \(faceLossAlertCount)/2)")
                sendToPresenceCheck()
            }
        }
        
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
        if !isMonitoring { return }
        if Date().timeIntervalSince(lastInterventionTime) < 30 { return }
        if isListening || isSpeaking { return }
        lastInterventionTime = Date()
        let msg = "System Alert: Distress detected (\(reason)). HR: \(Int(currentHeartRate)). Reassure user."
        
        // Interject if needed
        stopListening(sendData: false)
        audioPlayer?.stop()
        sendToBackend(text: msg)
    }
    
    // --- 6. MICROPHONE LOGIC (MASTER CONTROL) ---
    func startListening() {
        // A. INTERRUPTION LOGIC: If AI is speaking, shut it up and listen to user
        if isSpeaking {
            print("👆 User Interruption detected!")
            audioPlayer?.stop()
            audioPlayer?.delegate = nil // Stop the "DidFinish" callback loop
            DispatchQueue.main.async { self.isSpeaking = false }
        }
        
        // A. If already listening, do nothing (Button tap will act as STOP in UI)
        if isListening { return }
        
        // B. Reset State
        silenceTimer?.invalidate()
        if recognitionTask != nil { recognitionTask?.cancel(); recognitionTask = nil }
        
        // C. Force Audio Session to Record Mode
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { print("Audio Session Error: \(error)") }
        
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
        do {
            try audioEngine.start()
            DispatchQueue.main.async { self.isListening = true; self.spokenText = "I'm listening..." }
        } catch {
            print("Engine Start Error: \(error)")
            return
        }
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                DispatchQueue.main.async { self.spokenText = result.bestTranscription.formattedString }
                
                // RESET SILENCE TIMER ON EVERY WORD
                self.resetSilenceTimer()
                
                if result.isFinal { self.stopListening(sendData: true) }
            }
            if error != nil { self.stopListening(sendData: false) }
        }
    }
    
    // Detects when you stop talking
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { _ in
            print("🤫 Silence detected (Auto-Send).")
            self.stopListening(sendData: true)
        }
    }
    
    func stopListening(sendData: Bool) {
        silenceTimer?.invalidate() // Kill timer immediately
        
        if !isListening && !audioEngine.isRunning { return }
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask = nil
        audioEngine.reset()
        
        DispatchQueue.main.async { self.isListening = false }
        
        // Valid Input Check
        if sendData && spokenText.count > 1 && spokenText != "I'm listening..." && spokenText != "Press mic to speak..." {
            DispatchQueue.main.async { self.serverResponse = "Thinking..." }
            sendToBackend(text: self.spokenText)
        } else if isMonitoring && !isSpeaking {
            // If we heard nothing/junk, and we aren't speaking, just listen again
            // startListening() // Uncomment this if you want it to be VERY aggressive
        }
    }
    
    // --- 7. NETWORKING ---
    func sendToBackend(text: String, isSilentLog: Bool = false) {
        // REPLACE WITH YOUR IP
        let laptopIP = "192.168.1.55"
        guard let url = URL(string: "http://\(laptopIP):8000/listen") else { return }
        
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["text": text]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { print("Net: \(error)"); return }
            if isSilentLog { return }
            guard let data = data else { return }
            
            if data.first != 123 { // Audio
                DispatchQueue.main.async { self.playAudio(data: data) }
            } else {
                DispatchQueue.main.async {
                    self.serverResponse = "Logged."
                    // If no audio back, just listen again
                    if self.isMonitoring { self.startListening() }
                }
            }
        }.resume()
    }
    
    func sendToPresenceCheck() {
        let laptopIP = "192.168.1.55"
        guard let url = URL(string: "http://\(laptopIP):8000/is-there") else { return }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { print("IsThere Error: \(error)"); return }
            guard let data = data else { return }
            if !data.isEmpty && data.first != 123 {
                 DispatchQueue.main.async {
                    print("🔊 Playing Presence Check Audio")
                    self.stopListening(sendData: false) // Stop mic so we can speak
                    self.playAudio(data: data)
                }
            }
        }.resume()
    }
    
    // --- 8. AUDIO PLAYER (AUTO-RESUME) ---
    func playAudio(data: Data) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            self.audioPlayer = try AVAudioPlayer(data: data)
            self.audioPlayer?.delegate = self // Listen for finish
            self.audioPlayer?.prepareToPlay()
            self.audioPlayer?.play()
            
            DispatchQueue.main.async {
                self.isSpeaking = true
                self.serverResponse = "Speaking..."
            }
            
        } catch { print("Play Error: \(error)") }
    }
    
    // DELEGATE: Called when Audio Finishes
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("✅ Audio Finished. Resuming Listening...")
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.serverResponse = "Listening..."
            
            // AUTO-RESUME LISTENING
            if self.isMonitoring {
                self.startListening()
            }
        }
    }
}
