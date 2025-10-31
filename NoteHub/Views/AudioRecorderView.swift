import SwiftUI
import AVFoundation
import CoreData
import UniformTypeIdentifiers

struct AudioRecorderView: View {
    @ObservedObject var audioManager = AudioRecorderManager.shared
    let note: Note
    let onRecordingSaved: (AudioRecording) -> Void
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var isTranscribing = false
    @State private var transcriptionProgress: Double = 0
    @State private var transcriptionError: String?
    @State private var transcribedText: String = ""
    @State private var showTranscriptionResult = false
    @State private var txtFileURL: URL?
    @State private var showDocumentPicker = false

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
                            } else if isTranscribing {
                                ProgressView()
                                    .scaleEffect(1.5)
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
                
                if isTranscribing {
                    VStack(spacing: 12) {
                        Text("Идет транскрипция...")
                            .font(.headline)
                        Text("Модель загружается, это может занять несколько минут")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        ProgressView(value: transcriptionProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(width: 200)
                    }
                    .padding()
                }
                
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
                    } else if !isTranscribing {
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
                    .disabled(isTranscribing)
                }
            }
            .alert("Ошибка записи", isPresented: .constant(audioManager.recordingError != nil)) {
                Button("OK") { audioManager.recordingError = nil }
            } message: {
                Text(audioManager.recordingError ?? "")
            }
            .alert("Транскрипция завершена", isPresented: $showTranscriptionResult) {
                Button("Вставить в заметку и открыть TXT") {
                    insertTranscriptionToNote()
                    openTXTFile()
                }
                Button("Только открыть TXT") {
                    openTXTFile()
                }
                Button("Отмена", role: .cancel) {
                    dismiss()
                }
            } message: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Транскрибированный текст:")
                        .font(.headline)
                    
                    ScrollView {
                        Text(transcribedText.isEmpty ? "[Текст не распознан]" : transcribedText)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding(4)
                    }
                    .frame(maxHeight: 150)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    
                    if let txtURL = txtFileURL {
                        Text("TXT файл готов к сохранению")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .alert("Ошибка транскрипции", isPresented: .constant(transcriptionError != nil)) {
                Button("OK") {
                    transcriptionError = nil
                    dismiss()
                }
            } message: {
                Text(transcriptionError ?? "")
            }
            .sheet(isPresented: $showDocumentPicker) {
                if let url = txtFileURL {
                    DocumentPicker(url: url)
                }
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
                    audioManager.recordingError = "Доступ к микрофону запрещён. Разрешите в настройках."
                }
            }
        }
    }
    
    private func stopRecording() {
        guard let audioURL = audioManager.stopRecording() else {
            print("STOP: Ошибка — аудио не записано")
            return
        }
        
        print("STOP: Аудио сохранено: \(audioURL.path)")
        
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: audioURL.path) else {
            print("STOP: Файл не найден")
            return
        }
        
        let audioRecording = AudioRecording(context: viewContext)
        audioRecording.id = UUID()
        audioRecording.fileName = audioURL.lastPathComponent
        audioRecording.duration = audioManager.recordingTime
        audioRecording.createdAt = Date()
        audioRecording.note = note
        
        do {
            try viewContext.save()
            onRecordingSaved(audioRecording)
            print("STOP: AudioRecording сохранён")
            
            startTranscription(audioURL: audioURL)
            
        } catch {
            audioManager.recordingError = "Ошибка сохранения: \(error.localizedDescription)"
        }
    }
    
    private func startTranscription(audioURL: URL) {
        isTranscribing = true
        transcriptionProgress = 0
        transcribedText = ""
        txtFileURL = nil
        
        Task {
            do {
                let transcribedTextResult = try await WhisperLocalManager.shared.transcribeAudio(
                    audioURL: audioURL,
                    model: "tiny",
                    language: "ru",
                    format: "text",
                    progress: { progress in
                        DispatchQueue.main.async {
                            self.transcriptionProgress = progress
                        }
                    }
                )
                
                // Сохраняем в TXT файл
                let savedTxtURL = try await saveTXTToDownloads(txtText: transcribedTextResult, audioURL: audioURL)
                
                await MainActor.run {
                    self.transcribedText = transcribedTextResult
                    self.txtFileURL = savedTxtURL
                    self.isTranscribing = false
                    self.showTranscriptionResult = true
                }
                
            } catch {
                await MainActor.run {
                    self.transcriptionError = "Ошибка транскрипции: \(error.localizedDescription)"
                    self.isTranscribing = false
                }
            }
        }
    }
    
    private func saveTXTToDownloads(txtText: String, audioURL: URL) async throws -> URL {
        let fileName = "\(audioURL.deletingPathExtension().lastPathComponent)_transcription.txt"
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let txtURL = documentsURL.appendingPathComponent(fileName)
        
        try txtText.write(to: txtURL, atomically: true, encoding: .utf8)
        print("TXT сохранён: \(txtURL.path)")
        
        return txtURL
    }
    
    private func openTXTFile() {
        guard let txtURL = txtFileURL else { return }
        showDocumentPicker = true
    }
    
    private func insertTranscriptionToNote() {
        guard !transcribedText.isEmpty else { return }
        
        let currentText = note.text ?? ""
        let transcriptionHeader = "\n\n--- Транскрипция ---\n"
        note.text = currentText + transcriptionHeader + transcribedText
        
        updateAttributedTextWithTranscription()
        
        do {
            try viewContext.save()
            print("NOTE: Текст транскрипции добавлен в заметку")
        } catch {
            print("NOTE: Ошибка сохранения транскрипции: \(error)")
        }
    }
    
    private func updateAttributedTextWithTranscription() {
        guard !transcribedText.isEmpty else { return }
        
        let transcriptionHeader = "\n\n--- Транскрипция ---\n"
        let fullTranscriptionText = transcriptionHeader + transcribedText
        
        let currentAttributedText: NSAttributedString
        if let data = note.textData,
           let attributed = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data) {
            currentAttributedText = attributed
        } else {
            currentAttributedText = NSAttributedString(string: note.text ?? "")
        }
        
        let newText = NSMutableAttributedString(attributedString: currentAttributedText)
        let transcriptionAttributed = NSAttributedString(
            string: fullTranscriptionText,
            attributes: [
                .font: UIFont.systemFont(ofSize: 16),
                .foregroundColor: UIColor.label
            ]
        )
        newText.append(transcriptionAttributed)
        
        note.textData = try? NSKeyedArchiver.archivedData(
            withRootObject: newText,
            requiringSecureCoding: false
        )
    }
    
    private func cancelRecording() {
        audioManager.cancelRecording()
        dismiss()
    }
}

// MARK: - Document Picker
struct DocumentPicker: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url])
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.dismiss()
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}

// MARK: - Анимация записи
struct RecordingAnimationView: View {
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 30, height: 30)
            .scaleEffect(isAnimating ? 1.2 : 0.8)
            .animation(
                Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}
