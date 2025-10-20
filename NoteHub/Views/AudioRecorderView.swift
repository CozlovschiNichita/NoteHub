import SwiftUI
import AVFoundation
import CoreData

struct AudioRecorderView: View {
    @ObservedObject var audioManager = AudioRecorderManager.shared
    let note: Note
    let onRecordingSaved: (AudioRecording) -> Void
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()
                
                Circle()
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(width: 150, height: 150)
                    .overlay(
                        Group {
                            if audioManager.isRecording {
                                RecordingAnimationView()
                            } else {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.accentColor)
                            }
                        }
                    )
                
                Text(timeString(from: audioManager.recordingTime))
                    .font(.system(size: 36, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                
                Spacer()
                
                HStack(spacing: 50) {
                    if audioManager.isRecording {
                        Button(action: stopRecording) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.red)
                        }
                        
                        Button(action: cancelRecording) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                        }
                    } else {
                        Button(action: startRecording) {
                            Image(systemName: "record.circle")
                                .font(.system(size: 60))
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Запись голоса")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        audioManager.cancelRecording()
                        dismiss()
                    }
                }
            }
            .alert("Ошибка записи", isPresented: .constant(audioManager.recordingError != nil)) {
                Button("OK") {
                    audioManager.recordingError = nil
                }
            } message: {
                Text(audioManager.recordingError ?? "")
            }
        }
    }
    
    private func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func startRecording() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    _ = audioManager.startRecording(for: note.id ?? UUID())
                } else {
                    audioManager.recordingError = "Доступ к микрофону запрещен. Разрешите доступ в настройках."
                }
            }
        }
    }
    
    private func stopRecording() {
        guard let audioURL = audioManager.stopRecording() else { return }
        
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: audioURL.path) else { return }
        
        let audioRecording = AudioRecording(context: viewContext)
        audioRecording.id = UUID()
        audioRecording.fileName = audioURL.lastPathComponent
        audioRecording.duration = audioManager.recordingTime
        audioRecording.createdAt = Date()
        audioRecording.note = note
        
        do {
            try viewContext.save()
            onRecordingSaved(audioRecording)
            dismiss()
        } catch {
            audioManager.recordingError = "Ошибка сохранения записи: \(error.localizedDescription)"
        }
    }
    
    private func cancelRecording() {
        audioManager.cancelRecording()
        dismiss()
    }
}

struct RecordingAnimationView: View {
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 30, height: 30)
            .scaleEffect(isAnimating ? 1.2 : 0.8)
            .animation(
                Animation.easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}
