import UIKit

enum AttachmentParagraphStyle {
    static func make(for baseFont: UIFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .natural
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 0.5
        style.paragraphSpacingBefore = baseFont.pointSize * 0.25
        style.paragraphSpacing = baseFont.pointSize * 0.5
        style.headIndent = 0
        style.firstLineHeadIndent = 0
        style.tailIndent = 0
        return style
    }

    static func body(for baseFont: UIFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .natural
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 0.5
        style.paragraphSpacingBefore = 0
        style.paragraphSpacing = baseFont.pointSize * 0.25
        return style
    }

    static func stableTrailing(for baseFont: UIFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .natural
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 0.5
        style.paragraphSpacingBefore = baseFont.pointSize * 0.1
        style.paragraphSpacing = baseFont.pointSize * 0.25
        return style
    }

    // Новый стиль для параграфа с изображением
    static func attachment(for imageHeight: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byClipping // Запрещает переносы
        style.lineSpacing = 0
        style.paragraphSpacingBefore = 12
        style.paragraphSpacing = 12
        style.headIndent = 0
        style.firstLineHeadIndent = 0
        style.tailIndent = 0
        if #available(iOS 13.0, *) {
            style.minimumLineHeight = imageHeight // Фиксируем высоту строки
            style.maximumLineHeight = imageHeight
        }
        return style
    }
}
