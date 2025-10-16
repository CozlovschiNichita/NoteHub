import UIKit

/// Canonical paragraph style for attachment blocks to prevent newline coalescing and layout jumps.
enum AttachmentParagraphStyle {
    static func make(for baseFont: UIFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .natural
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 0.5 // Увеличим для стабильности
        style.paragraphSpacingBefore = baseFont.pointSize * 0.25
        style.paragraphSpacing = baseFont.pointSize * 0.5
        style.headIndent = 0
        style.firstLineHeadIndent = 0
        style.tailIndent = 0
        return style
    }

    /// A neutral body paragraph style (ensures consistency around attachments).
    static func body(for baseFont: UIFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .natural
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 0.5
        style.paragraphSpacingBefore = 0
        style.paragraphSpacing = baseFont.pointSize * 0.25
        return style
    }
    
    /// Stable style for text after images
    static func stableTrailing(for baseFont: UIFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .natural
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 0.5
        style.paragraphSpacingBefore = baseFont.pointSize * 0.1
        style.paragraphSpacing = baseFont.pointSize * 0.25
        return style
    }
}
