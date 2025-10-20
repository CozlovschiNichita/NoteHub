import Foundation
import AVFoundation
import Combine

final class AudioRecorderManager: NSObject, ObservableObject {
    static let shared = AudioRecorderManager()
    
    private var audioRecorder: AVAudioRecorder?
    private var audioSession: AVAudioSession = .sharedInstance()
    
    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0
    @Published var recordingError: String?
    
    private var timer: Timer?
    private var currentRecordingURL: URL?
    
    private override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
        } catch {
            recordingError = "Ошибка настройки аудио: \(error.localizedDescription)"
        }
    }
    
    func startRecording(for noteId: UUID) -> URL? {
        guard !isRecording else { return nil }
        
        let fileName = "\(noteId.uuidString)_\(UUID().uuidString).m4a"
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = documentsURL.appendingPathComponent(fileName)
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()
            
            isRecording = true
            recordingTime = 0
            currentRecordingURL = audioURL
            
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                self.recordingTime += 1
            }
            
            return audioURL
        } catch {
            recordingError = "Ошибка начала записи: \(error.localizedDescription)"
            return nil
        }
    }
    
    func stopRecording() -> URL? {
        guard isRecording else { return nil }
        
        audioRecorder?.stop()
        isRecording = false
        timer?.invalidate()
        timer = nil
        
        let finalURL = currentRecordingURL
        currentRecordingURL = nil
        
        return finalURL
    }
    
    func cancelRecording() {
        guard isRecording else { return }
        
        audioRecorder?.stop()
        if let url = currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        isRecording = false
        timer?.invalidate()
        timer = nil
        currentRecordingURL = nil
    }
}

extension AudioRecorderManager: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        isRecording = false
        timer?.invalidate()
        timer = nil
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        recordingError = "Ошибка записи: \(error?.localizedDescription ?? "Неизвестная ошибка")"
        isRecording = false
        timer?.invalidate()
        timer = nil
    }
}
