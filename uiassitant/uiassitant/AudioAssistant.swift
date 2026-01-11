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
    private var isProcessingRequest = false // THE SHIELD
    
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
        
        // Initial Audio Setup
        configureAudioSession()
        
        // Auto-start
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.startListeningSequence()
        }
    }
    
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // OPTIMIZED FOR VOLUME:
            // 1. .playAndRecord: Required for mic + speaker.
            // 2. .default: Standard audio processing (often louder than videoChat).
            // 3. .defaultToSpeaker: The critical option.
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
            // Force the override immediately
            try session.overrideOutputAudioPort(.speaker)
        } catch { print("❌ Session Error: \(error)") }
    }
    
    // Helper to AGGRESSIVELY force loud speaker
    private func forceSpeaker() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Reset override to none first (sometimes helps "jiggle" the state)
            try session.overrideOutputAudioPort(.none)
            // Then force speaker
            try session.overrideOutputAudioPort(.speaker)
        } catch {
            print("🔊 Speaker Override Failed: \(error)")
        }
    }
    
    // --- START / STOP ---
    func startPresageMonitoring() {
        isMonitoring = true
        
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
    
    // 2. START LISTENING
    func startListeningSequence() {
        if isProcessingRequest { return } // Shield Check
        
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
        } catch { print("❌ Engine Error: \(error)"); return }
        
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { result, error in
            if self.isProcessingRequest { return } // Shield Check
            
            if let result = result {
                DispatchQueue.main.async { self.spokenText = result.bestTranscription.formattedString }
                self.resetSilenceTimer()
            }
        }
    }
    
    // 3. SILENCE DETECTED
    private func resetSilenceTimer() {
        if isProcessingRequest { return }
        
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { _ in
            print("🤫 Silence detected. Sending...")
            self.sendDataToBackend()
        }
    }
    
    // 4. SEND DATA
    func sendDataToBackend() {
        isProcessingRequest = true // ENGAGE SHIELD
        let messageToSend = self.spokenText
        nukeAudio()
        
        if messageToSend.isEmpty || messageToSend == "Listening..." || messageToSend == "Speaking..." {
            isProcessingRequest = false
            startListeningSequence()
            return
        }
        
        DispatchQueue.main.async {
            self.isSpeaking = true
            self.spokenText = "Thinking..."
        }
        
        guard let url = URL(string: "http://\(serverIP):8000/listen") else {
            isProcessingRequest = false
            return
        }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["text": messageToSend]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
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
    
    // 5. PLAY AUDIO (THE VOLUME FIX)
    func playAudio(data: Data) {
        do {
            // 1. Force Session Active
            try AVAudioSession.sharedInstance().setActive(true)
            
            // 2. FORCE SPEAKER OUTPUT AGGRESSIVELY
            forceSpeaker()
            
            // 3. Setup Player
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.volume = 1.0 // Max Volume
            audioPlayer?.prepareToPlay()
            
            let success = audioPlayer?.play() ?? false
            
            if success {
                DispatchQueue.main.async {
                    self.isSpeaking = true
                    self.spokenText = "Speaking..."
                }
                
                // Watchdog
                let duration = audioPlayer?.duration ?? 2.0
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
    
    // 6. FINISH
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("✅ AI Finished.")
        finishTurn()
    }
    
    func finishTurn() {
        speakingTimer?.invalidate()
        isProcessingRequest = false // RELEASE SHIELD
        startListeningSequence()
    }
    
    // --- EMERGENCY ---
    func triggerEmergency() {
        isProcessingRequest = true
        nukeAudio()
        let msg = "EMERGENCY: User requested immediate help."
        guard let url = URL(string: "http://\(serverIP):8000/listen") else { return }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": msg])
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data, data.first != 123 {
                DispatchQueue.main.async { self.playAudio(data: data) }
            } else {
                DispatchQueue.main.async { self.finishTurn() }
            }
        }.resume()
    }
    
    // --- VITALS ---
    func processSensorData() {
        if !isMonitoring { return }
        guard let metrics = SmartSpectraSwiftSDK.shared.metricsBuffer else { return }
        let hr = Double(metrics.pulse.rate.last?.value ?? 0.0)
        let br = Double(metrics.breathing.rate.last?.value ?? 0.0)
        
        var face = false
        if let edge = SmartSpectraSwiftSDK.shared.edgeMetrics { face = edge.hasFace }
        
        DispatchQueue.main.async {
            self.currentHeartRate = hr
            self.currentBreathingRate = br
            self.isFacePresent = face
            
            if hr > 100 && br > 20 { self.isHighStress = true }
            else { self.isHighStress = false }
        }
    }
}
