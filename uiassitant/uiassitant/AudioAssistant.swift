import Foundation
import Speech
import AVFoundation
import SwiftUI
import Combine
import SmartSpectraSwiftSDK

// Inherit from NSObject to fix the 'super.init' error
class AudioAssistant: NSObject, ObservableObject {
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
    
    // Counter to prevent infinite "Are you there" loops
    private var faceLossAlertCount: Int = 0
    
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
        
        // Check if already running to prevent crash
        if SmartSpectraVitalsProcessor.shared.processingStatus == .processing {
            startDataLoop()
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
        
        // Start Reading Data Loop
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            if self.isMonitoring {
                self.startDataLoop()
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
        print("🛑 STOPPING SENSORS")
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        
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
        sendToBackend(text: msg)
    }
    
    // --- 6. MICROPHONE LOGIC (FIXED) ---
    func startListening() {
        // 1. Cleanup previous tasks
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        // 2. FORCE AUDIO SESSION RESET (The Fix for "Second Time" bug)
        // We must tell iOS: "Stop Playing, Start Recording" explicitly
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Deactivate first to reset state
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            // Configure for recording
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            // Reactivate
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio Session Error: \(error)")
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        
        // 3. SECURE TAP REMOVAL
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0) // Always remove before adding
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        // 4. START ENGINE
        audioEngine.prepare()
        do {
            try audioEngine.start()
            DispatchQueue.main.async { self.isListening = true; self.spokenText = "Listening..." }
        } catch {
            print("Engine Start Error: \(error)")
            return
        }
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                DispatchQueue.main.async { self.spokenText = result.bestTranscription.formattedString }
                if result.isFinal { self.stopListening(sendData: true) }
            }
            if error != nil {
                // Don't print error if it's just a cancellation
                // print("Speech Error: \(error!)")
                self.stopListening(sendData: false)
            }
        }
    }
    
    func stopListening(sendData: Bool) {
        if !isListening && !audioEngine.isRunning { return }
        
        // 1. Stop Everything
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask = nil
        
        // 2. RESET ENGINE (Crucial for next time)
        audioEngine.reset()
        
        DispatchQueue.main.async { self.isListening = false }
        
        if sendData && spokenText != "Listening..." && spokenText != "Press mic to speak..." {
            sendToBackend(text: self.spokenText)
        }
    }
    
    // --- 7. NETWORKING ---
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
    
    // --- 8. PRESENCE CHECK ---
    func sendToPresenceCheck() {
        let laptopIP = "172.17.79.245"
        guard let url = URL(string: "http://\(laptopIP):8000/is-there") else { return }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { print("IsThere Error: \(error)"); return }
            guard let data = data else { return }
            if !data.isEmpty && data.first != 123 {
                 DispatchQueue.main.async {
                    print("🔊 Playing Presence Check Audio")
                    self.playAudio(data: data)
                }
            }
        }.resume()
    }
    
    // --- 9. AUDIO PLAYER ---
    func playAudio(data: Data) {
        do {
            // FORCE SPEAKER OUTPUT
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            self.audioPlayer = try AVAudioPlayer(data: data)
            self.audioPlayer?.prepareToPlay()
            self.audioPlayer?.play()
            
            DispatchQueue.main.async { self.isSpeaking = true }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + (audioPlayer?.duration ?? 2)) {
                self.isSpeaking = false
                self.serverResponse = "Listening..."
            }
        } catch { print("Play Error: \(error)") }
    }
}
