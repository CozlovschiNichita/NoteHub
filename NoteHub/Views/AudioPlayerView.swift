import SwiftUI
import AVFoundation
import Combine
import CoreData

struct AudioPlayerView: View {
    let audioRecording: AudioRecording
    var onDelete: (() -> Void)?
    @StateObject private var audioPlayer = AudioPlayer()
    @State private var progress: Double = 0
    @State private var isExpanded: Bool = false
    @Environment(\.managedObjectContext) private var viewContext
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: audioRecording.createdAt ?? Date())
    }
    
    private var durationString: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: audioRecording.duration) ?? "0:00"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform")
                    .foregroundColor(.blue)
                    .font(.system(size: 14))
                
                Text("Аудиозапись")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(durationString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            
            Text(formattedDate)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if isExpanded {
                HStack(spacing: 12) {
                    Button(action: togglePlayback) {
                        Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        
                        HStack {
                            Text(audioPlayer.currentTimeString)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Text("-\(audioPlayer.remainingTimeString)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button(action: deleteRecording) {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                            .foregroundColor(.red)
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
        .onReceive(audioPlayer.$progress) { newProgress in
            progress = newProgress
        }
    }
    
    private func togglePlayback() {
        if audioPlayer.isPlaying {
            audioPlayer.pause()
        } else {
            let fileName = audioRecording.fileName ?? ""
            audioPlayer.playAudio(named: fileName)
        }
    }
    
    private func deleteRecording() {
        if audioPlayer.isPlaying {
            audioPlayer.pause()
        }
        
        let fileName = audioRecording.fileName ?? ""
        if !fileName.isEmpty {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let audioURL = documentsURL.appendingPathComponent(fileName)
            
            do {
                if FileManager.default.fileExists(atPath: audioURL.path) {
                    try FileManager.default.removeItem(at: audioURL)
                }
            } catch {
                return
            }
        }
        
        viewContext.delete(audioRecording)
        
        do {
            try viewContext.save()
            onDelete?()
        } catch {
            return
        }
    }
}

class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private var audioPlayer: AVAudioPlayer?
    
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var currentTimeString: String = "0:00"
    @Published var remainingTimeString: String = "0:00"
    
    private var timer: Timer?
    
    func playAudio(named fileName: String) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = documentsURL.appendingPathComponent(fileName)
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            return
        }
        
        guard FileManager.default.fileExists(atPath: audioURL.path) else { return }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            audioPlayer?.delegate = self
            audioPlayer?.volume = 1.0
            audioPlayer?.play()
            isPlaying = true
            
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, let player = self.audioPlayer else { return }
                
                if !player.isPlaying {
                    self.timer?.invalidate()
                    self.isPlaying = false
                    return
                }
                
                self.progress = player.currentTime / player.duration
                self.currentTimeString = self.timeString(from: player.currentTime)
                self.remainingTimeString = self.timeString(from: player.duration - player.currentTime)
            }
        } catch {
            return
        }
    }
    
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        timer?.invalidate()
    }
    
    private func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        progress = 0
        currentTimeString = "0:00"
        remainingTimeString = "0:00"
        timer?.invalidate()
        
        try? AVAudioSession.sharedInstance().setActive(false)
    }
    
    deinit {
        timer?.invalidate()
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
