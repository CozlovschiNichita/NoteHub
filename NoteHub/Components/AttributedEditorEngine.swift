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
        guard let tv = textView else { return }

        // Prepare attributed fragment: [attachment] + "\n"
        let imgString = NSMutableAttributedString(attachment: att)
        imgString.addAttribute(.link, value: link, range: NSRange(location: 0, length: imgString.length))

        let newline = NSAttributedString(string: "\n", attributes: [
            .font: defaultFont,
            .foregroundColor: UIColor.label,
            .paragraphStyle: AttachmentParagraphStyle.make(for: defaultFont)
        ])
        imgString.append(newline)

        let insertLocation = tv.selectedRange.location

        stabilizer?.performMutation(stabilizeTo: NSRange(location: insertLocation + imgString.length, length: 0)) { [weak self] in
            guard let self, let tv = self.textView else { return }
            let storage = tv.textStorage

            // Ensure surrounding paragraphs have consistent styles to avoid merging
            self.ensureStableParagraphStylesAround(location: insertLocation)

            storage.insert(imgString, at: insertLocation)

            // If we inserted into an empty line that already had a newline after, avoid double newline
            if insertLocation + imgString.length < storage.length {
                let after = NSRange(location: insertLocation + imgString.length, length: 1)
                if after.location < storage.length {
                    let char = storage.attributedSubstring(from: after).string
                    if char == "\n" {
                        storage.deleteCharacters(in: after)
                    }
                }
            }
            
            // Fix paragraph styles after insertion
            self.fixParagraphStylesAroundAttachment(at: insertLocation)
            self.cleanTypingAttributes()
        }
    }

    // MARK: - Improved paragraph styling

    private func ensureStableParagraphStylesAround(location: Int) {
        guard let tv = textView else { return }
        let storage = tv.textStorage
        let fullLen = storage.length
        guard fullLen > 0 else { return }

        let bodyStyle = AttachmentParagraphStyle.body(for: defaultFont)
        let trailingStyle = AttachmentParagraphStyle.stableTrailing(for: defaultFont)

        // Apply styles to the paragraph where insertion happens
        let paragraphRange = (storage.string as NSString).paragraphRange(for: NSRange(location: min(location, fullLen - 1), length: 0))
        
        // Use trailing style if inserting after existing content
        let isInsertingAfterContent = location > 0 && location < fullLen
        let styleToApply = isInsertingAfterContent ? trailingStyle : bodyStyle
        
        storage.addAttributes([
            .paragraphStyle: styleToApply,
            .font: defaultFont,
            .foregroundColor: UIColor.label
        ], range: paragraphRange)
    }

    private func fixParagraphStylesAroundAttachment(at location: Int) {
        guard let tv = textView else { return }
        let storage = tv.textStorage
        let fullLen = storage.length
        
        // Find paragraph with attachment
        let attachmentParagraphRange = (storage.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
        
        // Apply stable style to paragraph after attachment
        let nextParagraphStart = attachmentParagraphRange.location + attachmentParagraphRange.length
        if nextParagraphStart < fullLen {
            let nextParagraphRange = (storage.string as NSString).paragraphRange(for: NSRange(location: nextParagraphStart, length: 0))
            storage.addAttributes([
                .paragraphStyle: AttachmentParagraphStyle.stableTrailing(for: defaultFont),
                .font: defaultFont,
                .foregroundColor: UIColor.label
            ], range: nextParagraphRange)
        }
    }

    // MARK: - Formatting

    func applyFormatting(bold: Bool?, italic: Bool?, underline: Bool?, headerLevel: Int?) {
        guard let tv = textView else { return }
        let sel = tv.selectedRange

        // Compute target font sizes
        let bodySize = (tv.typingAttributes[.font] as? UIFont)?.pointSize ?? defaultFont.pointSize
        let h1 = bodySize * 1.6
        let h2 = bodySize * 1.35
        let h3 = bodySize * 1.2

        func font(from base: UIFont) -> UIFont {
            var traits: UIFontDescriptor.SymbolicTraits = []
            let currentDesc = base.fontDescriptor
            let currentTraits = currentDesc.symbolicTraits
            if currentTraits.contains(.traitBold) { traits.insert(.traitBold) }
            if currentTraits.contains(.traitItalic) { traits.insert(.traitItalic) }

            if let b = bold {
                if b { traits.insert(.traitBold) } else { traits.remove(.traitBold) }
            }
            if let i = italic {
                if i { traits.insert(.traitItalic) } else { traits.remove(.traitItalic) }
            }

            var targetSize = base.pointSize
            if let h = headerLevel {
                switch h {
                case 1: targetSize = h1
                case 2: targetSize = h2
                case 3: targetSize = h3
                default: targetSize = bodySize
                }
            }

            if let newDesc = currentDesc.withSymbolicTraits(traits) {
                return UIFont(descriptor: newDesc, size: targetSize)
            } else {
                if traits.contains([.traitBold, .traitItalic]) {
                    if let d = UIFont.systemFont(ofSize: targetSize).fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic]) {
                        return UIFont(descriptor: d, size: targetSize)
                    }
                }
                if traits.contains(.traitBold) { return UIFont.boldSystemFont(ofSize: targetSize) }
                if traits.contains(.traitItalic) { return UIFont.italicSystemFont(ofSize: targetSize) }
                return UIFont.systemFont(ofSize: targetSize)
            }
        }

        stabilizer?.performMutation(stabilizeTo: sel) { [weak self] in
            guard let self, let tv = self.textView else { return }
            let storage = tv.textStorage

            if sel.length == 0 {
                var typing = tv.typingAttributes
                let base = (typing[.font] as? UIFont) ?? self.defaultFont
                typing[.font] = font(from: base)
                if let u = underline { typing[.underlineStyle] = (u ? NSUnderlineStyle.single.rawValue : 0) }
                typing[.foregroundColor] = UIColor.label
                typing[.paragraphStyle] = AttachmentParagraphStyle.body(for: self.defaultFont)
                typing.removeValue(forKey: .link)
                tv.typingAttributes = typing
            } else {
                let range = NSRange(location: sel.location, length: sel.length)
                storage.enumerateAttributes(in: range, options: []) { attrs, subRange, _ in
                    var newAttrs = attrs
                    let base = (attrs[.font] as? UIFont) ?? self.defaultFont
                    newAttrs[.font] = font(from: base)
                    if let u = underline { newAttrs[.underlineStyle] = (u ? NSUnderlineStyle.single.rawValue : 0) }
                    newAttrs[.foregroundColor] = UIColor.label
                    newAttrs[.paragraphStyle] = AttachmentParagraphStyle.body(for: self.defaultFont)
                    newAttrs.removeValue(forKey: .link)
                    storage.setAttributes(newAttrs, range: subRange)
                }
            }
            
            // Ensure stable styles after formatting
            self.ensureStableParagraphStylesAround(location: sel.location)
            self.cleanTypingAttributes()
        }
    }

    // MARK: - Utilities

    func resizeAttachmentBoundsToContainerWidth(for imageSize: CGSize) -> CGRect {
        guard let tv = textView else { return .zero }
        let horizontalInset = tv.textContainerInset.left + tv.textContainerInset.right
        let availableWidth = max(0, tv.bounds.width - horizontalInset)
        let ratio = imageSize.width / max(imageSize.height, 0.0001)
        let newWidth = min(availableWidth, imageSize.width)
        let newHeight = newWidth / max(ratio, 0.0001)
        return CGRect(x: 0, y: 0, width: newWidth, height: newHeight)
    }

    private func cleanTypingAttributes() {
        guard let tv = textView else { return }
        tv.typingAttributes[.foregroundColor] = UIColor.label
        tv.typingAttributes[.font] = defaultFont
        tv.typingAttributes[.paragraphStyle] = AttachmentParagraphStyle.body(for: defaultFont)
        tv.typingAttributes.removeValue(forKey: .link)
    }
}
