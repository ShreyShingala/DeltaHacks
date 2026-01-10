import Foundation
import Speech
import AVFoundation
import SwiftUI
import Combine
import SmartSpectraSwiftSDK

class AudioAssistant: ObservableObject {
    // SPEECH RECOGNITION (EARS)
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    // AUDIO PLAYER (MOUTH)
    private var audioPlayer: AVAudioPlayer?
    
    // UI VARIABLES
    @Published var spokenText = "Press mic to speak..."
    @Published var isListening = false
    @Published var serverResponse = "Waiting for server..."
    @Published var isSpeaking = false // To animate UI when AI talks
    
    // PRESAGE VARIABLES
    @Published var currentHeartRate: Double = 0.0
    @Published var currentFocus: Double = 0.0
    @Published var isHighStress: Bool = false
    
    private var monitoringTimer: Timer?
        
    // Cooldown so we don't spam the AI every second
    private var lastInterventionTime: Date = Date.distantPast
    private var interventionLength: TimeInterval = 10

    // Permissions
    func requestPermissions() async {
        // Configure and activate audio session for recording and playback
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            print("Audio Session Error: \(error)")
        }

        // Request speech recognition authorization
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authStatus in
                continuation.resume(returning: authStatus)
            }
        }

        DispatchQueue.main.async {
            switch status {
            case .authorized:
                self.serverResponse = "Speech authorized."
            case .denied:
                self.serverResponse = "Speech permission denied."
            case .restricted:
                self.serverResponse = "Speech restricted on this device."
            case .notDetermined:
                self.serverResponse = "Speech permission not determined."
            @unknown default:
                self.serverResponse = "Unknown speech status."
            }
        }
    }
    
    // --- 1. MICROPHONE LOGIC ---
    func startListening() {
        // Cancel existing tasks
        recognitionTask?.cancel()
        self.recognitionTask = nil
        
        // Setup Audio Session (PlayAndRecord is crucial to hear audio back!)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio Session Error: \(error)")
        }
        
        // Setup Request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        
        // Setup Input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.recognitionRequest?.append(buffer)
        }
        
        // Start Engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
            self.spokenText = ""
        } catch {
            print("Engine Start Error: \(error)")
        }
        
        // Start Recognition
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                DispatchQueue.main.async {
                    self.spokenText = result.bestTranscription.formattedString
                }
                if result.isFinal {
                    DispatchQueue.main.async {
                        self.stopListening(sendData: true)
                    }
                    return
                }
            }

            if let error = error {
                print("Recognition error: \(error)")
                DispatchQueue.main.async {
                    self.serverResponse = "Recognition error: \(error.localizedDescription)"
                    self.stopListening(sendData: false)
                }
            }
        }
    }
    
    func stopListening(sendData: Bool) {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        
        if sendData {
            sendToBackend(text: self.spokenText)
        }
    }
    
    // --- 2. NETWORKING LOGIC ---
    func sendToBackend(text: String) {
        let laptopIP = "172.17.79.245"
        guard let url = URL(string: "http://\(laptopIP):8000/listen") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["text": text]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        DispatchQueue.main.async { self.serverResponse = "Sending to Brain..." }
        print("Sending to \(url.absoluteString): \(text)")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { self.serverResponse = "Connection Error: \(error.localizedDescription)" }
                return
            }
            
            guard let data = data else { return }
            
            // CHECK: Did we get Audio (Bytes) or JSON (Text)?
            // If the first byte looks like JSON '{', we parse text. Otherwise, we play audio.
            let firstByte = data.first ?? 0
            if firstByte == 123 { // '{' in ASCII - It's JSON (Echo Mode)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    DispatchQueue.main.async {
                        self.serverResponse = "Server saw: \(json["you_said"] ?? "???")"
                    }
                }
            } else {
                // It's NOT JSON, assume it's Audio (MP3)
                DispatchQueue.main.async {
                    self.serverResponse = "Received Audio! Playing..."
                    self.playAudio(data: data)
                }
            }
        }.resume()
    }
    
    // --- 3. AUDIO PLAYER LOGIC ---
    func playAudio(data: Data) {
        do {
            // Force audio to speaker
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            self.audioPlayer = try AVAudioPlayer(data: data)
            self.audioPlayer?.prepareToPlay()
            self.audioPlayer?.play()
            
            DispatchQueue.main.async { self.isSpeaking = true }
            
            // Reset UI when audio finishes (rough estimate)
            let duration = self.audioPlayer?.duration ?? 2.0
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                self.isSpeaking = false
            }
            
        } catch {
            print("Playback failed: \(error)")
        }
    }
    
    
    func startPresageMonitoring() {
            // Initialize with API Key (Get this from the Presage Booth!)
            SmartSpectraSwiftSDK.shared.setApiKey("QyQg2fsIqw3lSMXVvWIyv6Snt6kid0Dsabg4QHQA") //
            
            // Poll data every 1.0 seconds
            monitoringTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                self.checkVitals()
            }
        }
        
        func checkVitals() {
            // 1. READ DATA from the SDK buffer
            // (Note: syntax might vary slightly based on the exact SDK version)
            guard let metrics = SmartSpectraSwiftSDK.shared.metricsBuffer else { return }
            
            // Extract values safely
            let heartRate = metrics.pulse.rate.last?.value ?? 0.0
            let focusScore = metrics.
            
            // Update UI
            DispatchQueue.main.async {
                self.currentHeartRate = Double(heartRate)
                self.currentFocus = focusScore
            }
            
            // 2. THE TRIGGER LOGIC
            // If Heart Rate is high (> 110) OR Focus is very low (< 30%)
            let isStressed = (heartRate > 110.0)
            let isConfused = (focusScore < 0.3)
            
            if (isStressed || isConfused) {
                DispatchQueue.main.async { self.isHighStress = true }
                triggerAutoHelp()
            } else {
                DispatchQueue.main.async { self.isHighStress = false }
            }
        }
        
        func triggerAutoHelp() {
            // Check Cooldown: Don't trigger if we just helped in the last 10 seconds
            if Date().timeIntervalSince(lastInterventionTime) < interventionLength {
                return
            }
            
            // Check State: Don't trigger if user is currently speaking or AI is speaking
            if isListening || isSpeaking {
                return
            }
            
            print("AUTOMATIC INTERVENTION TRIGGERED")
            lastInterventionTime = Date()
            
            // Send a specific context prompt to the backend
            let contextMessage = "System Alert: User signs of distress detected. Heart Rate: \(Int(currentHeartRate)), Focus: \(Int(currentFocus * 100))%. Please reassure them."
            
            sendToBackend(text: contextMessage)
        }
}

