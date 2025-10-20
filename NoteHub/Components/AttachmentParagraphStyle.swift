import UIKit

enum AttachmentParagraphStyle {
    static func make(for baseFont: UIFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .natural
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 4
        style.paragraphSpacingBefore = 8
        style.paragraphSpacing = 8
        style.headIndent = 0
        style.firstLineHeadIndent = 0
        style.tailIndent = 0
        return style
    }

    static func body(for baseFont: UIFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .natural
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 4
        style.paragraphSpacingBefore = 0
        style.paragraphSpacing = 8
        return style
    }

    static func stableTrailing(for baseFont: UIFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .natural
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 4
        style.paragraphSpacingBefore = 4
        style.paragraphSpacing = 8
        return style
    }

    // Стиль для параграфа с изображением
    static func attachment(for imageHeight: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping // Возвращаем нормальный перенос
        style.lineSpacing = 0
        style.paragraphSpacingBefore = 8
        style.paragraphSpacing = 8
        style.headIndent = 0
        style.firstLineHeadIndent = 0
        style.tailIndent = 0
        
        // ВАЖНО: Устанавливаем фиксированную высоту строки равной высоте изображения
        style.minimumLineHeight = imageHeight
        style.maximumLineHeight = imageHeight
        
        return style
    }
}
