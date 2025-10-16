import SwiftUI
import CoreData
import AVFoundation
import UIKit

// MARK: - NoteDetailView
struct NoteDetailView: View {
    @ObservedObject var note: Note
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

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

    // Fullscreen preview
    @State private var isShowingFullImage: Bool = false
    @State private var fullImage: UIImage?

    // Measured width of the editor content area (to avoid UIScreen.main)
    @State private var editorContentWidth: CGFloat = 0

    @State private var isSavingImage: Bool = false

    // Formatting sheet
    @State private var showFormatSheet = false
    @State private var wantBold = false
    @State private var wantItalic = false
    @State private var wantUnderline = false
    @State private var headerLevel: Int = 0 // 0 = none, 1..3 = H1..H3

    // Bottom bar height for insetting the editor
    @State private var bottomBarHeight: CGFloat = 0

    // Дебаунсер для сохранения заметки
    @State private var saveTask: Task<Void, Never>? = nil

    var startEditing: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Заголовок
                TextField("Title", text: $editedTitle)
                    .font(.title)
                    .padding(.horizontal)
                    .padding(.top, 2)
                    .onChange(of: editedTitle) { _ in
                        debouncedSaveNote()
                    }

                Divider()

                // Текстовый редактор
                FormattedTextView(
                    attributedText: $editedText,
                    isFirstResponder: $isEditorFocused,
                    controller: textController,
                    bottomContentInset: bottomBarHeight + 12 // keep last line above the panel
                )
                .padding(.horizontal)
                .frame(maxHeight: .infinity)
                .background(Color(UIColor.systemBackground))
                // Measure available width for image sizing (instead of UIScreen.main)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { editorContentWidth = proxy.size.width }
                            .onChange(of: proxy.size) { _, newSize in
                                editorContentWidth = newSize.width
                            }
                    }
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(editedTitle.isEmpty ? "" : editedTitle)
            .sheet(isPresented: $showMediaPicker) {
                mediaPickerView
            }
            .onChange(of: selectedImage) { _, newValue in
                handleSelectedImage(newValue)
            }
            // .onChange(of: editedText) — УБИРАЕМ, не хотим @State обновлять каждый символ
            // .onChange(of: editorContentWidth) — УБИРАЕМ вызов restoreMediaInText

            .alert("Camera Access Required", isPresented: $showCameraAlert) {
                Button("Settings") { openAppSettings() }
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
                // Подготовка note -> editedText и callbacks
                setupNote()

                // Когда UITextView меняет текст — синхронизируем и сохраняем
                textController.onTextChange = { [weak textController] newText, event in
                    // Не заменяем attributedText на каждое изменение при наборе или вставке медиа,
                    // чтобы не вызывать пересоздание текста и скачки прокрутки.
                    switch event {
                    case .userFinishedEditing:
                        self.editedText = newText
                        debouncedSaveNote()
                    case .mediaInserted:
                        // НЕ присваиваем editedText здесь — UITextView уже содержит правильный текст.
                        // Просто сохраняем.
                        debouncedSaveNote()
                    case .other:
                        break
                    }
                }

                // Когда пользователь тапает по картинке — открываем оригинал
                textController.onImageTap = { fileName in
                    if let img = MediaManager.shared.loadImage(named: fileName) {
                        self.fullImage = img
                        self.isShowingFullImage = true
                    }
                }
            }
            .onDisappear {
                handleDisappear()
            }

            // Bottom bar: Undo | Add Photo | Format | Redo
            bottomBar
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { bottomBarHeight = proxy.size.height }
                            .onChange(of: proxy.size) { _, newSize in
                                bottomBarHeight = newSize.height
                            }
                    }
                )

            // Fullscreen preview with pinch-to-zoom
            if isShowingFullImage, let image = fullImage {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button(action: {
                            isShowingFullImage = false
                            fullImage = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                                .padding()
                        }
                    }
                    .padding(.top, 8)

                    // Zoomable image that initially fits the screen and supports pinch and double-tap
                    ZoomableImageView(image: image)
                        .ignoresSafeArea()

                    Spacer(minLength: 0)
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .sheet(isPresented: $showFormatSheet) {
            NavigationView {
                Form {
                    Section(header: Text("Style")) {
                        Toggle("Bold", isOn: $wantBold)
                        Toggle("Italic", isOn: $wantItalic)
                        Toggle("Underline", isOn: $wantUnderline)
                    }
                    Section(header: Text("Header")) {
                        Picker("Level", selection: $headerLevel) {
                            Text("None").tag(0)
                            Text("H1").tag(1)
                            Text("H2").tag(2)
                            Text("H3").tag(3)
                        }
                        .pickerStyle(.segmented)
                    }
                    Section(footer: Text("Tip: If no text is selected, the chosen styles become your default typing style.")) {
                        EmptyView()
                    }
                }
                .navigationTitle("Format")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showFormatSheet = false }
                    }
                    // Clear formatting: resets typing (or selection) to normal body style
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Clear") {
                            textController.applyFormatting(
                                bold: false,
                                italic: false,
                                underline: false,
                                headerLevel: 0 // reset to body size
                            )
                            showFormatSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            // Apply only what user picked; leave others unchanged (nil)
                            let b: Bool? = wantBold ? true : nil
                            let i: Bool? = wantItalic ? true : nil
                            let u: Bool? = wantUnderline ? true : nil
                            let h: Int? = headerLevel > 0 ? headerLevel : nil
                            textController.applyFormatting(bold: b, italic: i, underline: u, headerLevel: h)
                            showFormatSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 24) {
            // Undo
            Button {
                textController.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            // Add Photo (centered, with menu)
            Menu {
                Button { handleCameraSelection() } label: { Label("Take Photo", systemImage: "camera") }
                Button { handlePhotoLibrarySelection() } label: { Label("Choose from Library", systemImage: "photo.on.rectangle") }
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.accentColor, in: Circle())
                    .shadow(radius: 3)
            }

            // Format
            Button {
                // reset picks each time (optional)
                wantBold = false
                wantItalic = false
                wantUnderline = false
                headerLevel = 0
                showFormatSheet = true
            } label: {
                Image(systemName: "textformat")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            // Redo
            Button {
                textController.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(VisualEffectView(effect: UIBlurEffect(style: .systemMaterial)))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Subviews

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
        case .authorized: completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in completion(granted) }
        case .denied, .restricted: completion(false)
        @unknown default: completion(false)
        }
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func handleSelectedImage(_ newImage: UIImage?) {
        guard let image = newImage else { return }

        // Ensure note has an id so media files can be named and associated
        let noteId: UUID = {
            if let id = note.id { return id }
            let newId = UUID()
            note.id = newId
            return newId
        }()

        isSavingImage = true // блокируем выход

        textController.insertImage(image, noteId: noteId) { originalName, thumbnailName in
            DispatchQueue.main.async {
                guard let original = originalName else {
                    isSavingImage = false
                    selectedImage = nil
                    return
                }

                // безопасно обновляем photoPath
                var paths = note.photoPath?
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? []
                paths.append(original)
                note.photoPath = paths.joined(separator: ",")

                // сохраняем заметку
                do {
                    try viewContext.save()
                } catch {
                    print("Failed to save note after inserting image: \(error)")
                }

                isSavingImage = false
                selectedImage = nil

                // Не переустанавливаем editedText здесь — это вызовет пересоздание текста и скачок.
                // Сохранение произойдёт через debouncedSaveNote() в onTextChange(.mediaInserted)
            }
        }
    }

    /// Загрузка note -> editedText; проводим санитизацию (удаляем attachments из сохранённой версии)
    private func setupNote() {
        editedTitle = note.title ?? ""

        if let data = note.textData,
           let attributed = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data) {
            editedText = attributed
        } else {
            editedText = NSAttributedString(string: note.text ?? "")
        }

        // restoreMediaInText только тут! (НЕ дергать на каждое изменение ширины)
        let widthSnapshot = self.editorContentWidth
        DispatchQueue.global(qos: .userInitiated).async {
            restoreMediaInText(using: widthSnapshot)
        }

        if startEditing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isEditorFocused = true
            }
        }
    }

    /// Восстанавливает thumbnails в тексте (заменяет placeholder c .link = "media://file" на реальный NSTextAttachment -> thumbnail)
    private func restoreMediaInText(using containerWidth: CGFloat? = nil) {
        let base = NSMutableAttributedString(attributedString: editedText)

        let fullRange = NSRange(location: 0, length: base.length)
        var pairs: [(range: NSRange, fileName: String)] = []

        base.enumerateAttribute(.link, in: fullRange, options: []) { value, range, _ in
            if let s = value as? String, s.hasPrefix("media://") {
                let substring = base.attributedSubstring(from: range).string
                if substring == "\u{FFFC}" {
                    let file = s.replacingOccurrences(of: "media://", with: "")
                    pairs.append((range: range, fileName: file))
                }
            }
        }

        if pairs.isEmpty {
            DispatchQueue.main.async {
                if let tv = self.textController.textView {
                    tv.attributedText = base
                }
                self.editedText = base
            }
            return
        }

        let measuredWidth = containerWidth ?? self.editorContentWidth
        let containerW = measuredWidth > 0 ? measuredWidth : 400

        for pair in pairs.reversed() {
            let fileName = pair.fileName
            if let thumb = MediaManager.shared.loadThumbnail(named: fileName) {
                let attachment = MediaAttachment()
                attachment.fileName = fileName
                attachment.image = thumb

                let ratio = thumb.size.width / thumb.size.height
                let newWidth = min(max(containerW - 40, 0), thumb.size.width)
                let newHeight = newWidth / max(ratio, 0.0001)
                attachment.bounds = CGRect(x: 0, y: 0, width: newWidth, height: newHeight)

                let imageString = NSMutableAttributedString(attachment: attachment)
                imageString.addAttribute(.link, value: "media://\(fileName)", range: NSRange(location: 0, length: imageString.length))
                imageString.append(NSAttributedString(string: "\n\n"))

                base.replaceCharacters(in: pair.range, with: imageString)
            } else {
                base.replaceCharacters(in: pair.range, with: NSAttributedString(string: ""))
            }
        }

        DispatchQueue.main.async {
            if let tv = self.textController.textView {
                tv.attributedText = base
            }
            self.editedText = base
        }
    }

    private func handleDisappear() {
        guard !isSavingImage else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                handleDisappear()
            }
            return
        }

        if editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            editedText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            MediaManager.shared.cleanupMedia(for: note)
            viewContext.delete(note)
            try? viewContext.save()
        } else {
            saveTask?.cancel()
            saveNote() // Финальное принудительное сохранение
        }
    }

    @MainActor
    private func saveNote() {
        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        note.title = trimmedTitle.isEmpty ? "New note" : trimmedTitle
        note.text = editedText.string
        note.createdAt = Date()
        let sanitized = sanitizedAttributedForSaving(from: editedText)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: sanitized, requiringSecureCoding: false) {
            note.textData = data
        }
        do {
            try viewContext.save()
        } catch {
            print("Failed to save: \(error.localizedDescription)")
        }
    }

    /// Дебаунсер сохранения (0.7 сек после последнего действия)
    private func debouncedSaveNote() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            await saveNote()
        }
    }

    private func sanitizedAttributedForSaving(from attr: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attr)
        let placeholderChar = "\u{FFFC}"

        var attachmentRanges: [NSRange] = []
        mutable.enumerateAttribute(.attachment, in: NSRange(location: 0, length: mutable.length), options: []) { value, range, _ in
            if value != nil {
                attachmentRanges.append(range)
            }
        }
        for range in attachmentRanges.reversed() {
            var finalLink = (mutable.attribute(.link, at: range.location, effectiveRange: nil) as? String)
            if finalLink == nil,
               let att = mutable.attribute(.attachment, at: range.location, effectiveRange: nil) as? MediaAttachment,
               let file = att.fileName {
                finalLink = "media://\(file)"
            }
            let placeholder = NSMutableAttributedString(string: placeholderChar)
            if let link = finalLink {
                placeholder.addAttribute(.link, value: link, range: NSRange(location: 0, length: placeholder.length))
            }
            if range.location < mutable.length {
                let attrs = mutable.attributes(at: range.location, effectiveRange: nil)
                for (k, v) in attrs {
                    if k != .attachment && k != .link {
                        placeholder.addAttribute(k, value: v, range: NSRange(location: 0, length: placeholder.length))
                    }
                }
            }
            mutable.replaceCharacters(in: range, with: placeholder)
        }

        var mediaLinkRanges: [(NSRange, String)] = []
        mutable.enumerateAttribute(.link, in: NSRange(location: 0, length: mutable.length), options: []) { value, range, _ in
            if let s = value as? String, s.hasPrefix("media://") {
                mediaLinkRanges.append((range, s))
            }
        }
        for (range, link) in mediaLinkRanges.reversed() {
            let substring = mutable.attributedSubstring(from: range).string
            if substring == placeholderChar && range.length == 1 { continue }
            let placeholder = NSMutableAttributedString(string: placeholderChar)
            placeholder.addAttribute(.link, value: link, range: NSRange(location: 0, length: 1))
            if range.location < mutable.length {
                let attrs = mutable.attributes(at: range.location, effectiveRange: nil)
                for (k, v) in attrs {
                    if k != .attachment && k != .link {
                        placeholder.addAttribute(k, value: v, range: NSRange(location: 0, length: 1))
                    }
                }
            }
            mutable.replaceCharacters(in: range, with: placeholder)
        }

        return mutable
    }
}

