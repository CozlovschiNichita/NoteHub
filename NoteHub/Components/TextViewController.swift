import UIKit
import Combine
import AVFoundation
import SwiftUI

// MARK: - TextChangeEvent
enum TextChangeEvent {
    case userFinishedEditing
    case mediaInserted
    case other
}

// MARK: - TextViewController
/// Контроллер, управляющий UITextView из SwiftUI (FormattedTextView).
/// Содержит API для вставки изображений, форматирования, undo/redo и синхронизации с SwiftUI.
final class TextViewController: ObservableObject {
    weak var textView: UITextView? {
        didSet {
            if let tv = textView {
                engine = AttributedEditorEngine(textView: tv)
                engine?.defaultFont = defaultFont
            } else {
                engine = nil
            }
        }
    }

    var onTextChange: ((NSAttributedString, TextChangeEvent) -> Void)?
    var onImageTap: ((String) -> Void)?

    // Config
    private let defaultFont = UIFont.systemFont(ofSize: 18)

    // Engine
    private var engine: AttributedEditorEngine?

    // MARK: - Undo / Redo
    func undo() { textView?.undoManager?.undo() }
    func redo() { textView?.undoManager?.redo() }

    func recordUndo(beforeChangeWithName name: String) {
        guard let um = textView?.undoManager else { return }
        um.beginUndoGrouping()
        if !name.isEmpty { um.setActionName(name) }
    }

    func endUndo() {
        textView?.undoManager?.endUndoGrouping()
    }

    // MARK: - Sync helpers
    func syncToSwiftUI(event: TextChangeEvent = .other) {
        guard let tv = textView else { return }
        onTextChange?(tv.attributedText ?? NSAttributedString(string: ""), event)
    }

    func setText(_ text: NSAttributedString, selectedRange: NSRange) {
        guard let tv = textView else { return }
        let currentText = tv.attributedText ?? NSAttributedString(string: "")
        let currentRange = tv.selectedRange

        tv.undoManager?.beginUndoGrouping()
        tv.undoManager?.registerUndo(withTarget: self) { controller in
            controller.setText(currentText, selectedRange: currentRange)
        }

        // Set once (initial load/undo only), not during typing
        tv.attributedText = text
        let safeRange = clampedRange(for: text, desired: selectedRange)
        tv.selectedRange = safeRange
        onTextChange?(text, .other)

        tv.undoManager?.endUndoGrouping()
    }

    func clampedRange(for text: NSAttributedString, desired: NSRange) -> NSRange {
        let length = text.length
        guard length > 0 else { return NSRange(location: 0, length: 0) }
        let loc = max(0, min(desired.location, length))
        let maxLen = max(0, length - loc)
        let len = max(0, min(desired.length, maxLen))
        return NSRange(location: loc, length: len)
    }

    // MARK: - Formatting
    func applyFormatting(bold: Bool?, italic: Bool?, underline: Bool?, headerLevel: Int?) {
        guard let _ = textView else { return }
        recordUndo(beforeChangeWithName: "Format")
        engine?.applyFormatting(bold: bold, italic: italic, underline: underline, headerLevel: headerLevel)
        if let t = textView?.attributedText { onTextChange?(t, .other) }
        endUndo()
    }

    // MARK: - Media: вставка изображения
    func insertImage(_ image: UIImage, noteId: UUID, completion: @escaping (String?, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let result = MediaManager.shared.saveImage(image, for: noteId) else {
                DispatchQueue.main.async { completion(nil, nil) }
                return
            }
            let thumbnail = MediaManager.shared.loadThumbnail(named: result.thumbnail) ?? image

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { // Небольшая задержка для стабильности
                guard let tv = self.textView, let engine = self.engine else {
                    completion(nil, nil)
                    return
                }

                self.recordUndo(beforeChangeWithName: "Insert Image")

                let att = MediaAttachment()
                att.fileName = result.original
                att.image = thumbnail
                att.bounds = engine.resizeAttachmentBoundsToContainerWidth(for: thumbnail.size)

                engine.insertAttachment(att, link: "media://\(result.original)")

                if let t = tv.attributedText {
                    self.onTextChange?(t, .mediaInserted)
                }

                self.endUndo()
                completion(result.original, result.thumbnail)
            }
        }
    }
}
