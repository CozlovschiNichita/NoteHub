import SwiftUI
import CoreData
import AVFoundation
import UIKit
import Photos
import PhotosUI

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

    // Measured width of the editor content area
    @State private var editorContentWidth: CGFloat = 0
    @State private var isSavingImage: Bool = false

    // Formatting sheet
    @State private var showFormatSheet = false
    
    // Текущие состояния форматирования
    @State private var currentBold: Bool = false
    @State private var currentItalic: Bool = false
    @State private var currentUnderline: Bool = false
    @State private var currentHeaderLevel: Int = 0

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
                    bottomContentInset: bottomBarHeight + 12
                )
                .padding(.horizontal)
                .frame(maxHeight: .infinity)
                .background(Color(UIColor.systemBackground))
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
                setupNote()
                
                textController.onTextChange = { [weak textController] newText, event in
                    switch event {
                    case .userFinishedEditing:
                        self.editedText = newText
                        debouncedSaveNote()
                    case .mediaInserted:
                        debouncedSaveNote()
                    case .other:
                        self.editedText = newText
                        debouncedSaveNote()
                    }
                }

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

            // Bottom bar
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

            // Fullscreen preview
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
                    Section(header: Text("Стиль текста")) {
                        Toggle("Жирный", isOn: $currentBold)
                            .onChange(of: currentBold) { newValue in
                                if !newValue && currentHeaderLevel > 0 {
                                    currentHeaderLevel = 0
                                }
                            }
                        Toggle("Курсив", isOn: $currentItalic)
                        Toggle("Подчеркивание", isOn: $currentUnderline)
                    }
                    Section(header: Text("Заголовок")) {
                        Picker("Уровень", selection: $currentHeaderLevel) {
                            Text("Основной текст").tag(0)
                            Text("Заголовок H1").tag(1)
                            Text("Заголовок H2").tag(2)
                            Text("Заголовок H3").tag(3)
                            Text("Заголовок H4").tag(4)
                            Text("Заголовок H5").tag(5)
                            Text("Заголовок H6").tag(6)
                        }
                        .pickerStyle(.wheel)
                        .onChange(of: currentHeaderLevel) { newValue in
                            if newValue > 0 {
                                currentBold = true
                            }
                        }
                    }
                    
                    Section(header: Text("Текущие настройки")) {
                        HStack {
                            Text("Статус:")
                            Spacer()
                            Text(formattingStatusString())
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    
                    Section(header: Text("Как работает")) {
                        Text("Настройки применяются к тексту, который вы будете вводить дальше")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .navigationTitle("Стиль текста")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") {
                            showFormatSheet = false
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Сбросить всё") {
                            resetAllFormatting()
                            showFormatSheet = false
                        }
                        .foregroundColor(.red)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Применить") {
                            applyFormatting()
                            showFormatSheet = false
                        }
                        .bold()
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .onAppear {
                updateFormattingStatesFromSelection()
            }
        }
    }

    // MARK: - Bottom Bar
    
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

            // Add Photo
            Menu {
                Button { handleCameraSelection() } label: { Label("Снять фото", systemImage: "camera") }
                Button { handlePhotoLibrarySelection() } label: { Label("Выбрать из галереи", systemImage: "photo.on.rectangle") }
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
                updateFormattingStatesFromSelection()
                showFormatSheet = true
            } label: {
                Image(systemName: "textformat")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Group {
                            if currentBold || currentItalic || currentUnderline || currentHeaderLevel > 0 {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 8, y: -8)
                            }
                        }
                    )
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

    private var mediaPickerView: some View {
        MediaPicker(
            selectedImage: $selectedImage,
            selectedVideoURL: .constant(nil),
            sourceType: mediaSourceType
        )
        .ignoresSafeArea()
    }
}

// MARK: - Formatting Methods
extension NoteDetailView {
    
    private func debugCurrentFormatting() {
        guard let textView = textController.textView else { return }
        
        let typingAttrs = textView.typingAttributes
        print("=== DEBUG FORMATTING ===")
        print("UI States - bold: \(currentBold), italic: \(currentItalic), underline: \(currentUnderline), header: \(currentHeaderLevel)")
        
        if let font = typingAttrs[.font] as? UIFont {
            let traits = font.fontDescriptor.symbolicTraits
            print("Current Font - name: \(font.fontName), size: \(font.pointSize)")
            print("Font Traits - bold: \(traits.contains(.traitBold)), italic: \(traits.contains(.traitItalic))")
        }
        
        let underline = (typingAttrs[.underlineStyle] as? Int) == NSUnderlineStyle.single.rawValue
        print("Underline: \(underline)")
        print("========================")
    }
    
    private func applyFormatting() {
        print("🔄 Applying formatting from UI - bold: \(currentBold), italic: \(currentItalic), underline: \(currentUnderline), header: \(currentHeaderLevel)")
        debugCurrentFormatting()
        
        textController.applyFormatting(
            bold: currentBold,
            italic: currentItalic,
            underline: currentUnderline,
            headerLevel: currentHeaderLevel
        )
        
        // Проверяем результат
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.debugCurrentFormatting()
        }
    }
    
    private func resetAllFormatting() {
        currentBold = false
        currentItalic = false
        currentUnderline = false
        currentHeaderLevel = 0
        
        textController.applyFormatting(
            bold: false,
            italic: false,
            underline: false,
            headerLevel: 0
        )
        
        print("🔄 Formatting reset to default")
    }

    private func formattingStatusString() -> String {
        var status: [String] = []
        
        if currentBold { status.append("Жирный") }
        if currentItalic { status.append("Курсив") }
        if currentUnderline { status.append("Подчёркивание") }
        if currentHeaderLevel > 0 { status.append("H\(currentHeaderLevel)") }
        
        return status.isEmpty ? "Обычный текст" : status.joined(separator: ", ")
    }
    
    private func updateFormattingStatesFromSelection() {
        guard let textView = textController.textView else { return }
        
        let selectedRange = textView.selectedRange
        if selectedRange.length > 0 {
            // Для выделенного: берем атрибуты из диапазона (усредняем, если mixed)
            var isBold = true
            var isItalic = true
            var isUnderline = true
            var headerSize: CGFloat = 18
            
            textView.attributedText.enumerateAttributes(in: selectedRange, options: []) { attrs, _, _ in
                if let font = attrs[.font] as? UIFont {
                    let traits = font.fontDescriptor.symbolicTraits
                    isBold = isBold && traits.contains(.traitBold)
                    isItalic = isItalic && traits.contains(.traitItalic)
                    headerSize = max(headerSize, font.pointSize) // Или логика для определения уровня
                }
                if let underlineValue = attrs[.underlineStyle] as? Int {
                    isUnderline = isUnderline && (underlineValue == NSUnderlineStyle.single.rawValue)
                }
            }
            
            currentBold = isBold
            currentItalic = isItalic
            currentUnderline = isUnderline
            
            // Определяем headerLevel по max size (примерно)
            switch headerSize {
            case 32: currentHeaderLevel = 1
            case 28: currentHeaderLevel = 2
            case 24: currentHeaderLevel = 3
            case 22: currentHeaderLevel = 4
            case 20: currentHeaderLevel = 5
            case 18 where currentBold: currentHeaderLevel = 6
            default: currentHeaderLevel = 0
            }
        } else {
            // Без выделения: typingAttributes (как сейчас)
            let typingAttrs = textView.typingAttributes
            
            if let font = typingAttrs[.font] as? UIFont {
                let traits = font.fontDescriptor.symbolicTraits
                currentBold = traits.contains(.traitBold)
                currentItalic = traits.contains(.traitItalic)
                
                let fontSize = font.pointSize
                if traits.contains(.traitBold) {
                    switch fontSize {
                    case 32: currentHeaderLevel = 1
                    case 28: currentHeaderLevel = 2
                    case 24: currentHeaderLevel = 3
                    case 22: currentHeaderLevel = 4
                    case 20: currentHeaderLevel = 5
                    case 18: currentHeaderLevel = 6
                    default: currentHeaderLevel = 0
                    }
                } else {
                    currentHeaderLevel = 0
                }
            }
            
            currentUnderline = (typingAttrs[.underlineStyle] as? Int) == NSUnderlineStyle.single.rawValue
        }
        
        print("🔍 Current formatting - bold: \(currentBold), italic: \(currentItalic), underline: \(currentUnderline), header: \(currentHeaderLevel)")
        debugCurrentFormatting()
    }
}

// MARK: - Other Methods
extension NoteDetailView {
    
    private func handleCameraSelection() {
        isCheckingPermissions = true

        checkCameraPermission { granted in
            DispatchQueue.main.async {
                self.isCheckingPermissions = false
                if granted {
                    self.mediaSourceType = .camera
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.showMediaPicker = true
                    }
                } else {
                    self.cameraError = "Camera access is required to take photos. Please enable camera access in Settings to use this feature."
                    self.showCameraAlert = true
                }
            }
        }
    }

    private func handlePhotoLibrarySelection() {
        isCheckingPermissions = true
        checkPhotoLibraryPermission { granted in
            DispatchQueue.main.async {
                self.isCheckingPermissions = false
                if granted {
                    self.mediaSourceType = .photoLibrary
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.showMediaPicker = true
                    }
                } else {
                    self.cameraError = "Photo library access is required to select photos. Please enable access in Settings."
                    self.showCameraAlert = true  // Reuse alert for library
                }
            }
        }
    }

    private func checkPhotoLibraryPermission(completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus()
        switch status {
        case .authorized, .limited:  // Handle limited too
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { newStatus in
                completion(newStatus == .authorized || newStatus == .limited)
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
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

        let noteId: UUID = {
            if let id = note.id { return id }
            let newId = UUID()
            note.id = newId
            return newId
        }()

        isSavingImage = true

        textController.insertImage(image, noteId: noteId) { originalName, thumbnailName in
            DispatchQueue.main.async {
                guard let original = originalName else {
                    self.isSavingImage = false
                    self.selectedImage = nil
                    return
                }

                var paths = note.photoPath?
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? []
                paths.append(original)
                note.photoPath = paths.joined(separator: ",")

                do {
                    try self.viewContext.save()
                } catch {
                    print("Failed to save note after inserting image: \(error)")
                }

                self.isSavingImage = false
                self.selectedImage = nil
            }
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

        let widthSnapshot = self.editorContentWidth
        DispatchQueue.global(qos: .userInitiated).async {
            self.restoreMediaInText(using: widthSnapshot)
        }

        if startEditing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isEditorFocused = true
            }
        }
    }

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
                self.handleDisappear()
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
            saveNote()
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
