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

    // MARK: - Formatting with explicit states
    func applyFormatting(bold: Bool, italic: Bool, underline: Bool, headerLevel: Int) {
        guard let tv = textView else { return }
        recordUndo(beforeChangeWithName: "Format")
        
        print("Applying formatting - bold: \(bold), italic: \(italic), underline: \(underline), header: \(headerLevel)")
        
        let targetSize: CGFloat
        switch headerLevel {
        case 1: targetSize = 32
        case 2: targetSize = 28
        case 3: targetSize = 24
        case 4: targetSize = 22
        case 5: targetSize = 20
        case 6: targetSize = 18
        default: targetSize = 18
        }
        
        let finalBold = headerLevel > 0 ? true : bold
        
        var newFont: UIFont
        if finalBold && italic {
            if let descriptor = UIFont.systemFont(ofSize: targetSize).fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic]) {
                newFont = UIFont(descriptor: descriptor, size: targetSize)
            } else {
                newFont = UIFont.boldSystemFont(ofSize: targetSize)
                if let italicDescriptor = newFont.fontDescriptor.withSymbolicTraits(.traitItalic) {
                    newFont = UIFont(descriptor: italicDescriptor, size: targetSize)
                } else {
                    newFont = UIFont.boldSystemFont(ofSize: targetSize)
                }
            }
        } else if finalBold {
            newFont = UIFont.boldSystemFont(ofSize: targetSize)
        } else if italic {
            newFont = UIFont.italicSystemFont(ofSize: targetSize)
        } else {
            newFont = UIFont.systemFont(ofSize: targetSize)
        }
        
        print("New font: \(newFont.fontName), size: \(newFont.pointSize), bold: \(finalBold), italic: \(italic)")
        
        let newAttributes: [NSAttributedString.Key: Any] = [
            .font: newFont,
            .underlineStyle: underline ? NSUnderlineStyle.single.rawValue : 0,
            .foregroundColor: UIColor.label
        ]
        
        let selectedRange = tv.selectedRange
        let offsetBefore = tv.contentOffset
        let rangeBefore = tv.selectedRange
        
        tv.textStorage.beginEditing()  // Batch changes
        
        if selectedRange.length > 0 {
            // In-place update без полной замены
            tv.textStorage.addAttributes(newAttributes, range: selectedRange)
        } else {
            // Для typing: merge, но перезаписать font/underline
            tv.typingAttributes = tv.typingAttributes.merging(newAttributes) { _, new in new }
        }
        
        // Ensure stable styles (из engine, для предотвращения jumps от paragraph)
        engine?.ensureStableParagraphStylesAround(location: selectedRange.location)
        
        tv.textStorage.endEditing()  // Apply batch
        
        // Restore position если jump
        tv.layoutIfNeeded()
        tv.setContentOffset(offsetBefore, animated: false)
        tv.selectedRange = rangeBefore
        
        // Обновляем состояние
        if let t = tv.attributedText {
            onTextChange?(t, .other)
        }
        
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

                // Restore font after insertion to prevent small text issue
                tv.typingAttributes[.font] = self.defaultFont

                if let t = tv.attributedText {
                    self.onTextChange?(t, .mediaInserted)
                }

                self.endUndo()
                completion(result.original, result.thumbnail)
            }
        }
    }
}
