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

    // УПРОЩЕННЫЙ стиль для параграфа с изображением - ТОЛЬКО для самого изображения
    static func attachment(for imageHeight: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 0
        style.paragraphSpacingBefore = 0  // Убрали отступы
        style.paragraphSpacing = 0        // Убрали отступы
        style.headIndent = 0
        style.firstLineHeadIndent = 0
        style.tailIndent = 0
        
        // ВАЖНО: Устанавливаем фиксированную высоту ТОЛЬКО для строки с изображением
        style.minimumLineHeight = imageHeight
        style.maximumLineHeight = imageHeight
        
        return style
    }

    // НОВЫЙ: Стиль для параграфа, который следует ЗА изображением
    static func afterAttachment(for baseFont: UIFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .natural
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 4
        style.paragraphSpacingBefore = 8  // Отступ перед текстом после изображения
        style.paragraphSpacing = 8
        style.headIndent = 0
        style.firstLineHeadIndent = 0
        style.tailIndent = 0
        return style
    }
}
