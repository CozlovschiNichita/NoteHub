import UIKit

/// Performs safe, stable text mutations on UITextView's textStorage to avoid caret jumps with attachments.
final class AttributedEditorEngine {
    weak var textView: UITextView?
    private var stabilizer: TextLayoutStabilizer?

    // Base typing font injected by owner
    var defaultFont: UIFont = UIFont.systemFont(ofSize: 18)

    init(textView: UITextView) {
        self.textView = textView
        self.stabilizer = TextLayoutStabilizer(textView: textView)
    }

    func updateTextView(_ tv: UITextView) {
        self.textView = tv
        self.stabilizer = TextLayoutStabilizer(textView: tv)
    }

    // MARK: - Media insertion

    func insertAttachment(_ att: MediaAttachment, link: String) {
        guard let tv = textView, let image = att.image else { return }

        // Рассчитываем bounds на полную ширину
        let fullBounds = resizeAttachmentBoundsToContainerWidth(for: image.size)
        att.bounds = fullBounds

        // Изолированный параграф для изображения
        let imgString = NSMutableAttributedString(attachment: att)
        imgString.addAttribute(.link, value: link, range: NSRange(location: 0, length: imgString.length))
        
        // Применяем специальный стиль для изображения
        let attachmentStyle = AttachmentParagraphStyle.attachment(for: fullBounds.height)
        imgString.addAttribute(.paragraphStyle, value: attachmentStyle, range: NSRange(location: 0, length: imgString.length))

        // Добавляем \n перед и после для полной изоляции
        let newline = NSAttributedString(string: "\n", attributes: [
            .font: defaultFont,
            .foregroundColor: UIColor.label,
            .paragraphStyle: AttachmentParagraphStyle.body(for: defaultFont)
        ])

        let fullInsertString = NSMutableAttributedString()
        fullInsertString.append(newline)
        fullInsertString.append(imgString)
        fullInsertString.append(newline)

        let insertLocation = tv.selectedRange.location

        stabilizer?.performMutation(stabilizeTo: NSRange(location: insertLocation + fullInsertString.length, length: 0)) { [weak self] in
            guard let self, let tv = self.textView else { return }
            let storage = tv.textStorage
            let offsetBefore = tv.contentOffset

            storage.beginEditing()

            // Очистка лишних переносов строк и принудительное разделение параграфа
            self.forceParagraphBreak(at: insertLocation, storage: storage)
            storage.insert(fullInsertString, at: insertLocation)

            // Применяем стабильные стили вокруг изображения
            self.fixAttachmentParagraphIsolation(at: insertLocation, attachmentLength: imgString.length, storage: storage)

            storage.endEditing()

            // Курсор после вставки
            let newCursorPosition = NSRange(location: insertLocation + fullInsertString.length, length: 0)
            tv.selectedRange = newCursorPosition

            // Сбрасываем typingAttributes для предотвращения наследования
            tv.typingAttributes = [
                .font: self.defaultFont,
                .paragraphStyle: AttachmentParagraphStyle.body(for: self.defaultFont),
                .foregroundColor: UIColor.label
            ]

            tv.layoutIfNeeded()
            tv.setContentOffset(offsetBefore, animated: false)
            tv.setNeedsDisplay()
        }
    }

    // MARK: - Attachment Isolation Helpers

    private func forceParagraphBreak(at location: Int, storage: NSTextStorage) {
        let fullLen = storage.length
        guard location >= 0 && location <= fullLen else { return }

        // Если не на границе параграфа, добавляем \n
        if location > 0 {
            let prevCharRange = NSRange(location: location - 1, length: 1)
            if prevCharRange.location < fullLen {
                let prevChar = storage.attributedSubstring(from: prevCharRange).string
                if prevChar != "\n" {
                    let newline = NSAttributedString(string: "\n", attributes: [
                        .font: defaultFont,
                        .paragraphStyle: AttachmentParagraphStyle.body(for: defaultFont)
                    ])
                    storage.insert(newline, at: location)
                }
            }
        }
    }

    private func fixAttachmentParagraphIsolation(at location: Int, attachmentLength: Int, storage: NSTextStorage) {
        let fullLen = storage.length

        // Параграф изображения (после \n)
        let attachmentStart = location + 1
        let attachmentRange = NSRange(location: attachmentStart, length: attachmentLength)
        if attachmentRange.location + attachmentRange.length <= fullLen {
            let attachmentParagraph = (storage.string as NSString).paragraphRange(for: attachmentRange)
            let attachmentStyle = AttachmentParagraphStyle.attachment(for: (storage.attribute(.attachment, at: attachmentStart, effectiveRange: nil) as? NSTextAttachment)?.bounds.height ?? defaultFont.lineHeight)
            storage.addAttributes([
                .paragraphStyle: attachmentStyle,
                .font: defaultFont
            ], range: attachmentParagraph)
        }

        // Следующий параграф (после \n)
        let nextParagraphStart = attachmentStart + attachmentLength + 1
        if nextParagraphStart < fullLen {
            let nextParagraph = (storage.string as NSString).paragraphRange(for: NSRange(location: nextParagraphStart, length: 0))
            storage.addAttributes([
                .paragraphStyle: AttachmentParagraphStyle.body(for: defaultFont),
                .font: defaultFont,
                .foregroundColor: UIColor.label
            ], range: nextParagraph)
        }
    }

    // MARK: - Improved paragraph styling

    func ensureStableParagraphStylesAround(location: Int) {
        guard let tv = textView else { return }
        let storage = tv.textStorage
        let fullLen = storage.length
        guard fullLen > 0 else { return }

        let bodyStyle = AttachmentParagraphStyle.body(for: defaultFont)
        let paragraphRange = (storage.string as NSString).paragraphRange(for: NSRange(location: min(location, fullLen - 1), length: 0))

        storage.addAttributes([
            .paragraphStyle: bodyStyle,
            .font: defaultFont,
            .foregroundColor: UIColor.label
        ], range: paragraphRange)
    }

    // MARK: - Formatting (synchronized with TextViewController)

    func applyFormatting(bold: Bool, italic: Bool, underline: Bool, headerLevel: Int) {
        guard let tv = textView else { return }
        let sel = tv.selectedRange

        let targetSize: CGFloat
        switch headerLevel {
        case 1: targetSize = 32
        case 2: targetSize = 28
        case 3: targetSize = 24
        case 4: targetSize = 22
        case 5: targetSize = 20
        case 6: targetSize = 18
        default: targetSize = defaultFont.pointSize
        }

        let finalBold = headerLevel > 0 ? true : bold

        func createFont(size: CGFloat, bold: Bool, italic: Bool) -> UIFont {
            if bold && italic {
                if let descriptor = UIFont.systemFont(ofSize: size).fontDescriptor
                    .withSymbolicTraits([.traitBold, .traitItalic]) {
                    return UIFont(descriptor: descriptor, size: size)
                }
            } else if bold {
                return UIFont.boldSystemFont(ofSize: size)
            } else if italic {
                return UIFont.italicSystemFont(ofSize: size)
            }
            return UIFont.systemFont(ofSize: size)
        }

        let newFont = createFont(size: targetSize, bold: finalBold, italic: italic)

        let newAttributes: [NSAttributedString.Key: Any] = [
            .font: newFont,
            .underlineStyle: underline ? NSUnderlineStyle.single.rawValue : 0,
            .foregroundColor: UIColor.label,
            .paragraphStyle: AttachmentParagraphStyle.body(for: defaultFont)
        ]

        stabilizer?.performMutation(stabilizeTo: sel) { [weak self] in
            guard let self, let tv = self.textView else { return }
            let storage = tv.textStorage
            let offsetBefore = tv.contentOffset

            storage.beginEditing()

            if sel.length == 0 {
                tv.typingAttributes = newAttributes
            } else {
                storage.addAttributes(newAttributes, range: sel)
                storage.removeAttribute(.link, range: sel)
            }

            self.ensureStableParagraphStylesAround(location: sel.location)
            storage.endEditing()

            tv.layoutIfNeeded()
            tv.setContentOffset(offsetBefore, animated: false)
        }
    }

    // MARK: - Utilities

    func resizeAttachmentBoundsToContainerWidth(for imageSize: CGSize) -> CGRect {
        guard let tv = textView else { return .zero }
        // Используем полную ширину UITextView (без учета отступов, так как они уже 0 в FormattedTextView)
        let availableWidth = tv.bounds.width
        let ratio = imageSize.height / max(imageSize.width, 0.0001)
        let newWidth = availableWidth
        let newHeight = newWidth * ratio
        return CGRect(x: 0, y: 0, width: newWidth, height: newHeight)
    }

    private func cleanTypingAttributes() {
        guard let tv = textView else { return }
        tv.typingAttributes = [
            .font: defaultFont,
            .paragraphStyle: AttachmentParagraphStyle.body(for: defaultFont),
            .foregroundColor: UIColor.label
        ]
    }
}
