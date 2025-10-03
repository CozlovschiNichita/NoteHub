import UIKit
import Combine
import AVFoundation

// MARK: - TextViewController
final class TextViewController: ObservableObject {
    weak var textView: UITextView?
    
    // Callback для SwiftUI
    var onTextChange: ((NSAttributedString) -> Void)?
    // Callback при тапе на картинку
    var onImageTap: ((String) -> Void)?
    
    // MARK: - Undo helpers
    private func recordUndo(beforeChangeWithName name: String? = nil) {
        guard let tv = textView else { return }
        let oldText = tv.attributedText ?? NSAttributedString(string: "")
        let oldRange = tv.selectedRange
        let um = tv.undoManager
        um?.beginUndoGrouping()
        um?.registerUndo(withTarget: self) { controller in
            controller.setText(oldText, selectedRange: oldRange)
        }
        if let name { um?.setActionName(name) }
    }
    
    private func endUndo() {
        textView?.undoManager?.endUndoGrouping()
    }
    
    private func clampedRange(for text: NSAttributedString, desired: NSRange) -> NSRange {
        let length = text.length
        guard length > 0 else { return NSRange(location: 0, length: 0) }
        let loc = max(0, min(desired.location, length))
        let maxLen = max(0, length - loc)
        let len = max(0, min(desired.length, maxLen))
        return NSRange(location: loc, length: len)
    }
    
    func setText(_ text: NSAttributedString, selectedRange: NSRange) {
        guard let tv = textView else { return }
        // Register redo
        let currentText = tv.attributedText ?? NSAttributedString(string: "")
        let currentRange = tv.selectedRange
        tv.undoManager?.beginUndoGrouping()
        tv.undoManager?.registerUndo(withTarget: self) { controller in
            controller.setText(currentText, selectedRange: currentRange)
        }
        tv.attributedText = text
        let safeRange = clampedRange(for: text, desired: selectedRange)
        tv.selectedRange = safeRange
        onTextChange?(text)
        tv.undoManager?.endUndoGrouping()
    }
    
    func undo() {
        guard let tv = textView, let um = tv.undoManager, um.canUndo else { return }
        um.undo()
    }
    
    func redo() {
        guard let tv = textView, let um = tv.undoManager, um.canRedo else { return }
        um.redo()
    }
    
    // MARK: - Helper
    private func applyMutable(_ block: (NSMutableAttributedString) -> Void, actionName: String? = nil) {
        guard let tv = textView else { return }
        let range = tv.selectedRange
        recordUndo(beforeChangeWithName: actionName)
        let mutable = NSMutableAttributedString(attributedString: tv.attributedText ?? NSAttributedString(string: ""))
        block(mutable)
        tv.attributedText = mutable
        // Range length should still be valid for formatting operations, but clamp defensively
        let safeRange = clampedRange(for: mutable, desired: range)
        tv.selectedRange = safeRange
        onTextChange?(mutable)
        endUndo()
    }
    
    // MARK: - Bold / Italic
    func toggleTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let tv = textView else { return }
        let range = tv.selectedRange
        
        if range.length > 0 {
            applyMutable({ mutable in
                mutable.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                    let currentFont = (value as? UIFont) ?? UIFont.systemFont(ofSize: UIFont.systemFontSize)
                    var traits = currentFont.fontDescriptor.symbolicTraits
                    if traits.contains(trait) { traits.remove(trait) }
                    else { traits.insert(trait) }
                    if let newDescriptor = currentFont.fontDescriptor.withSymbolicTraits(traits) {
                        let newFont = UIFont(descriptor: newDescriptor, size: currentFont.pointSize)
                        mutable.addAttribute(.font, value: newFont, range: subRange)
                    }
                }
            }, actionName: "Format")
        } else {
            var currentFont = (tv.typingAttributes[.font] as? UIFont) ?? UIFont.systemFont(ofSize: UIFont.systemFontSize)
            var traits = currentFont.fontDescriptor.symbolicTraits
            if traits.contains(trait) { traits.remove(trait) }
            else { traits.insert(trait) }
            if let newDescriptor = currentFont.fontDescriptor.withSymbolicTraits(traits) {
                currentFont = UIFont(descriptor: newDescriptor, size: currentFont.pointSize)
                tv.typingAttributes[.font] = currentFont
            }
            onTextChange?(tv.attributedText)
        }
    }
    
    // MARK: - Underline
    func toggleUnderline() {
        guard let tv = textView else { return }
        let range = tv.selectedRange
        
        if range.length > 0 {
            applyMutable({ mutable in
                mutable.enumerateAttribute(.underlineStyle, in: range, options: []) { value, subRange, _ in
                    let current = (value as? Int) ?? 0
                    if current == 0 {
                        mutable.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: subRange)
                    } else {
                        mutable.removeAttribute(.underlineStyle, range: subRange)
                    }
                }
            }, actionName: "Format")
        } else {
            let current = (tv.typingAttributes[.underlineStyle] as? Int) ?? 0
            if current == 0 {
                tv.typingAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            } else {
                tv.typingAttributes.removeValue(forKey: .underlineStyle)
            }
            onTextChange?(tv.attributedText)
        }
    }
    
    // MARK: - Headers
    func makeHeader(level: Int) {
        guard let tv = textView else { return }
        let sizes: [CGFloat] = [28, 24, 20, 18, 16]
        let fontSize = sizes[max(0, min(level - 1, sizes.count - 1))]
        let headerFont = UIFont.boldSystemFont(ofSize: fontSize)
        let range = tv.selectedRange
        
        if range.length > 0 {
            applyMutable({ mutable in
                mutable.addAttribute(.font, value: headerFont, range: range)
            }, actionName: "Header")
        } else {
            tv.typingAttributes[.font] = headerFont
            onTextChange?(tv.attributedText)
        }
    }
}

// MARK: - Media Extension
extension TextViewController {
    /// Вставка изображения с использованием thumbnail
    func insertImage(_ image: UIImage, noteId: UUID, completion: @escaping (String?, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let result = MediaManager.shared.saveImage(image, for: noteId) else {
                DispatchQueue.main.async { completion(nil, nil) }
                return
            }
            
            // Загружаем thumbnail для отображения
            let thumbnail = MediaManager.shared.loadThumbnail(named: result.thumbnail) ?? image
            
            DispatchQueue.main.async {
                guard let tv = self.textView else {
                    completion(nil, nil)
                    return
                }
                
                // Record undo just once for the whole insertion
                self.recordUndo(beforeChangeWithName: "Insert Image")
                
                let attachment = NSTextAttachment()
                attachment.image = thumbnail
                
                let ratio = thumbnail.size.width / thumbnail.size.height
                // Учитываем отступы контейнера, чтобы картинка не выходила за контент
                let horizontalInset = tv.textContainerInset.left + tv.textContainerInset.right
                let availableWidth = max(0, tv.bounds.width - horizontalInset)
                let newWidth = min(availableWidth, thumbnail.size.width)
                let newHeight = newWidth / max(ratio, 0.0001)
                attachment.bounds = CGRect(x: 0, y: 0, width: newWidth, height: newHeight)
                
                // Добавляем .link только к вложению
                let imageString = NSMutableAttributedString(attachment: attachment)
                imageString.addAttribute(.link, value: "media://\(result.original)", range: NSRange(location: 0, length: imageString.length))
                
                let insertLocation = tv.selectedRange.location
                let mutable = NSMutableAttributedString(attributedString: tv.attributedText ?? NSAttributedString(string: ""))
                
                // Вставляем изображение и перенос строки
                mutable.insert(imageString, at: insertLocation)
                mutable.insert(NSAttributedString(string: "\n"), at: insertLocation + imageString.length)
                
                // ВАЖНО: убедиться, что перенос строки не наследует .link
                let newlineRange = NSRange(location: insertLocation + imageString.length, length: 1)
                if NSMaxRange(newlineRange) <= mutable.length {
                    mutable.removeAttribute(.link, range: newlineRange)
                }
                
                tv.attributedText = mutable
                // Ставим курсор после переноса (clamp defensively)
                let afterInsert = NSRange(location: insertLocation + imageString.length + 1, length: 0)
                let safeAfterInsert = self.clampedRange(for: mutable, desired: afterInsert)
                tv.selectedRange = safeAfterInsert
                
                // Сбрасываем .link из typingAttributes, чтобы следующий текст не был ссылкой
                tv.typingAttributes.removeValue(forKey: .link)
                
                self.onTextChange?(mutable)
                
                self.endUndo()
                
                // Возвращаем имена файлов: оригинал и thumbnail
                completion(result.original, result.thumbnail)
            }
        }
    }
    
    /// Извлечение медиа из текста
    func extractMediaFromText(_ attributedText: NSAttributedString) -> [String] {
        var mediaFiles: [String] = []
        attributedText.enumerateAttribute(.link, in: NSRange(location: 0, length: attributedText.length)) { value, _, _ in
            if let link = value as? String, link.hasPrefix("media://") {
                let fileName = link.replacingOccurrences(of: "media://", with: "")
                mediaFiles.append(fileName)
            }
        }
        return mediaFiles
    }
}

// MARK: - Explicit formatting application
extension TextViewController {
    /// Apply formatting explicitly (not toggling). Pass nil to leave an attribute unchanged.
    /// - Parameters:
    ///   - bold: true/false to force bold on/off; nil to keep as-is
    ///   - italic: true/false to force italic on/off; nil to keep as-is
    ///   - underline: true/false to force underline on/off; nil to keep as-is
    ///   - headerLevel: nil to keep size; 1...3 to set header size (and bold); 0 to reset to body size (18) and clear traits
    func applyFormatting(bold: Bool?, italic: Bool?, underline: Bool?, headerLevel: Int?) {
        guard let tv = textView else { return }
        let range = tv.selectedRange
        let applyToSelection = range.length > 0
        let defaultBodySize: CGFloat = 18

        func desiredFont(from current: UIFont) -> UIFont {
            var targetSize = current.pointSize
            var traits = current.fontDescriptor.symbolicTraits

            if let level = headerLevel {
                if level == 0 {
                    // Reset to normal body font
                    targetSize = defaultBodySize
                    traits.remove(.traitBold)
                    traits.remove(.traitItalic)
                } else {
                    let sizes: [CGFloat] = [28, 24, 20] // H1..H3
                    targetSize = sizes[max(0, min(level - 1, sizes.count - 1))]
                    traits.insert(.traitBold) // headers are bold
                }
            }
            if let b = bold {
                if b { traits.insert(.traitBold) } else { traits.remove(.traitBold) }
            }
            if let i = italic {
                if i { traits.insert(.traitItalic) } else { traits.remove(.traitItalic) }
            }

            if let descriptor = current.fontDescriptor.withSymbolicTraits(traits) {
                return UIFont(descriptor: descriptor, size: targetSize)
            } else {
                // Fallback if traits combo fails
                var base = UIFont.systemFont(ofSize: targetSize)
                if traits.contains(.traitBold) { base = UIFont.boldSystemFont(ofSize: targetSize) }
                if traits.contains(.traitItalic) { base = UIFont.italicSystemFont(ofSize: targetSize) }
                return base
            }
        }

        if applyToSelection {
            applyMutable({ mutable in
                // Font changes
                mutable.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                    let current = (value as? UIFont) ?? UIFont.systemFont(ofSize: UIFont.systemFontSize)
                    let newFont = desiredFont(from: current)
                    mutable.addAttribute(.font, value: newFont, range: subRange)
                }
                // Underline changes
                if let u = underline {
                    if u {
                        mutable.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                    } else {
                        mutable.removeAttribute(.underlineStyle, range: range)
                    }
                }
            }, actionName: "Format")
        } else {
            // Apply to typing attributes (default typing style)
            var currentFont = (tv.typingAttributes[.font] as? UIFont) ?? UIFont.systemFont(ofSize: UIFont.systemFontSize)
            currentFont = desiredFont(from: currentFont)
            tv.typingAttributes[.font] = currentFont

            if let u = underline {
                if u {
                    tv.typingAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                } else {
                    tv.typingAttributes.removeValue(forKey: .underlineStyle)
                }
            }
            onTextChange?(tv.attributedText)
        }
    }
}
