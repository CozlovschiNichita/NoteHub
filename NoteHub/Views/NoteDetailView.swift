import SwiftUI
import CoreData
import AVFoundation

// MARK: - NoteDetailView
struct NoteDetailView: View {
    @ObservedObject var note: Note
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var editedTitle: String = ""
    @State private var editedText: NSAttributedString = NSAttributedString(string: "")
    
    @State private var textController = TextViewController()
    @State private var isEditorFocused: Bool = false
    
    // Медиа состояния
    @State private var showMediaPicker = false
    @State private var mediaSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedImage: UIImage?
    @State private var showCameraAlert = false
    @State private var cameraError: String = ""
    @State private var isCheckingPermissions = false
    
    var startEditing: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Заголовок
            TextField("Title", text: $editedTitle)
                .font(.title)
                .padding(.horizontal)
                .padding(.top, 8)
            
            Divider()
            
            // Текстовый редактор
            FormattedTextView(
                attributedText: $editedText,
                isFirstResponder: $isEditorFocused,
                controller: textController
            )
            .padding(.horizontal)
            .frame(maxHeight: .infinity)
            .background(Color(UIColor.systemBackground))
            
            // Панель инструментов
            if isEditorFocused {
                toolbarView
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(editedTitle.isEmpty ? "" : editedTitle)
        .sheet(isPresented: $showMediaPicker) {
            mediaPickerView
        }
        .onChange(of: selectedImage) { oldValue, newValue in
            handleSelectedImage(newValue)
        }
        .onChange(of: editedText) { oldValue, newValue in
            saveNote()
        }
        .onChange(of: editedTitle) { oldValue, newValue in
            saveNote()
        }
        .alert("Camera Access Required", isPresented: $showCameraAlert) {
            Button("Settings") {
                openAppSettings()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(cameraError)
        }
        .overlay {
            if isCheckingPermissions {
                ProgressView("Checking permissions...")
                    .padding()
                    .background(Color.black.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .onAppear {
            setupNote()
        }
        .onDisappear {
            handleDisappear()
        }
    }
    
    // MARK: - Subviews
    
    private var toolbarView: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                FormatButton(systemImage: "bold") {
                    textController.toggleTrait(.traitBold)
                }
                FormatButton(systemImage: "italic") {
                    textController.toggleTrait(.traitItalic)
                }
                FormatButton(systemImage: "underline") {
                    textController.toggleUnderline()
                }
                
                cameraButton
                
                headersMenu
                
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(VisualEffectView(effect: UIBlurEffect(style: .systemMaterial)))
        }
    }
    
    private var cameraButton: some View {
        Menu {
            Button {
                handleCameraSelection()
            } label: {
                Label("Take Photo", systemImage: "camera")
            }
            
            Button {
                handlePhotoLibrarySelection()
            } label: {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
            }
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .padding(.horizontal)
    }
    
    private var headersMenu: some View {
        Menu {
            Button("H1") { textController.makeHeader(level: 1) }
            Button("H2") { textController.makeHeader(level: 2) }
            Button("H3") { textController.makeHeader(level: 3) }
        } label: {
            Image(systemName: "textformat.size")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .padding(.horizontal)
    }
    
    private var mediaPickerView: some View {
        MediaPicker(
            selectedImage: $selectedImage,
            selectedVideoURL: .constant(nil),
            sourceType: mediaSourceType
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Methods
    
    private func handleCameraSelection() {
        isCheckingPermissions = true
        
        checkCameraPermission { granted in
            DispatchQueue.main.async {
                isCheckingPermissions = false
                
                if granted {
                    mediaSourceType = .camera
                    // Небольшая задержка для стабильности
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showMediaPicker = true
                    }
                } else {
                    cameraError = "Camera access is required to take photos. Please enable camera access in Settings to use this feature."
                    showCameraAlert = true
                }
            }
        }
    }
    
    private func handlePhotoLibrarySelection() {
        mediaSourceType = .photoLibrary
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showMediaPicker = true
        }
    }
    
    private func checkCameraPermission(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                completion(granted)
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func handleSelectedImage(_ newImage: UIImage?) {
        guard let image = newImage, let noteId = note.id else { return }
        
        textController.insertImage(image, noteId: noteId) { fileName in
            if let fileName = fileName {
                updatePhotoPath(with: fileName)
                saveNote()
            }
            selectedImage = nil
        }
    }
    
    private func updatePhotoPath(with newFileName: String) {
        if let existingPath = note.photoPath, !existingPath.isEmpty {
            note.photoPath = existingPath + "," + newFileName
        } else {
            note.photoPath = newFileName
        }
    }
    
    private func setupNote() {
        editedTitle = note.title ?? ""
        
        if let data = note.textData,
           let attributed = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data) {
            editedText = attributed
        } else {
            editedText = NSAttributedString(string: note.text ?? "")
        }
        
        restoreMediaInText()
        
        if startEditing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isEditorFocused = true
            }
        }
        
        textController.onTextChange = { newText in
            self.editedText = newText
        }
    }
    
    private func restoreMediaInText() {
        guard let noteId = note.id else { return }
        
        if let photoPath = note.photoPath {
            let mediaFiles = photoPath.components(separatedBy: ",")
            for fileName in mediaFiles {
                let trimmedFileName = fileName.trimmingCharacters(in: .whitespaces)
                if !trimmedFileName.isEmpty, let image = MediaManager.shared.loadImage(named: trimmedFileName) {
                    textController.insertImage(image, noteId: noteId) { _ in }
                }
            }
        }
    }
    
    private func handleDisappear() {
        if editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            editedText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            MediaManager.shared.cleanupMedia(for: note)
            viewContext.delete(note)
            try? viewContext.save()
        } else {
            saveNote()
        }
    }
    
    private func saveNote() {
        note.title = editedTitle
        note.text = editedText.string
        note.createdAt = Date()
        
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: editedText, requiringSecureCoding: false) {
            note.textData = data
        }
        
        do {
            try viewContext.save()
        } catch {
            print("Failed to save: \(error.localizedDescription)")
        }
    }
}

// MARK: - FormatButton
struct FormatButton: View {
    let systemImage: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }
}

// MARK: - VisualEffectView
struct VisualEffectView: UIViewRepresentable {
    let effect: UIVisualEffect?
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: effect)
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = effect
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let note = Note(context: context)
    note.title = "Test Note"
    note.text = "Test content"
    note.id = UUID()
    return NavigationView {
        NoteDetailView(note: note, startEditing: true)
            .environment(\.managedObjectContext, context)
    }
}
