import Foundation
import Speech
import Observation

@Observable
final class VoiceCommandService: NSObject, SFSpeechRecognizerDelegate {
    static let shared = VoiceCommandService()
    
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "voiceCommandsEnabled") }
        set { 
            UserDefaults.standard.set(newValue, forKey: "voiceCommandsEnabled")
            if newValue { startListening() } else { stopListening() }
        }
    }
    
    var isListening: Bool = false
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    // ── Anti-spam: track what we've already acted on ──────────────────────────
    private var lastProcessedLength: Int = 0
    private var lastActionTime: Date = .distantPast
    private let cooldown: TimeInterval = 3.0  // seconds between accepted commands
    
    func start() {
        if isEnabled { startListening() }
    }
    
    func requestPermission() {
        SFSpeechRecognizer.requestAuthorization { status in
            // Handle status
        }
    }
    
    private func startListening() {
        guard !isListening else { return }
        
        // Cancel previous task
        recognitionTask?.cancel()
        recognitionTask = nil
        lastProcessedLength = 0
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        try? audioEngine.start()
        
        isListening = true
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let fullText = result.bestTranscription.formattedString.lowercased()
                // Only process NEW words since last check
                let newText = String(fullText.dropFirst(self.lastProcessedLength))
                self.lastProcessedLength = fullText.count
                
                if !newText.isEmpty {
                    self.processNewWords(newText)
                }
            }
            
            if error != nil || result?.isFinal == true {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.isListening = false
                
                // Restart listening if still enabled
                if self.isEnabled {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.startListening()
                    }
                }
            }
        }
    }
    
    private func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        isListening = false
    }
    
    /// Process only newly-recognised words (not the cumulative transcript).
    /// Requires the wake-word "study" to be present in the new segment,
    /// plus a specific action keyword.  This prevents ambient speech from
    /// accidentally triggering commands.
    private func processNewWords(_ text: String) {
        // Enforce cooldown — ignore rapid-fire triggers
        guard Date().timeIntervalSince(lastActionTime) > cooldown else { return }
        
        // ── Must contain wake word "study" in the same utterance ──────────
        guard text.contains("study") else { return }
        
        // ── Start command: "study start" / "start study" / "study begin" ──
        if text.contains("start") || text.contains("begin") {
            if StudyTimer.shared.state == .idle {
                lastActionTime = Date()
                DispatchQueue.main.async {
                    StudyTimer.shared.start()
                    SoundService.shared.playSessionStart()
                }
            }
            return
        }
        
        // ── Pause command: "study pause" / "pause study" ──────────────────
        if text.contains("pause") {
            if StudyTimer.shared.state == .running {
                lastActionTime = Date()
                DispatchQueue.main.async {
                    StudyTimer.shared.toggle()
                }
            }
            return
        }
        
        // ── Resume command: "study resume" / "resume study" / "study continue" ─
        if text.contains("resume") || text.contains("continue") {
            if StudyTimer.shared.state == .paused {
                lastActionTime = Date()
                DispatchQueue.main.async {
                    StudyTimer.shared.toggle()
                }
            }
            return
        }
        
        // ── Finish command: "study finish" / "finish study" / "study done" / "study end" ─
        if text.contains("finish") || text.contains("done") || text.contains("end") {
            if StudyTimer.shared.state != .idle {
                lastActionTime = Date()
                DispatchQueue.main.async {
                    if let data = StudyTimer.shared.finish() {
                        SessionEndWindowController.present(sessionData: data)
                    }
                }
            }
            return
        }
    }
}
