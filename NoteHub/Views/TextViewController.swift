import UIKit
import Combine

// MARK: - TextViewController
final class TextViewController: ObservableObject {
    weak var textView: UITextView?
    
    // Callback для SwiftUI
    var onTextChange: ((NSAttributedString) -> Void)?
    
    private func applyMutable(_ block: (NSMutableAttributedString) -> Void) {
        guard let tv = textView else { return }
        let range = tv.selectedRange
        let mutable = NSMutableAttributedString(attributedString: tv.attributedText ?? NSAttributedString(string: ""))
        block(mutable)
        tv.attributedText = mutable
        tv.selectedRange = range
        
        // Обновляем SwiftUI
        onTextChange?(mutable)
    }
    
    // MARK: - Bold / Italic
    func toggleTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let tv = textView else { return }
        let range = tv.selectedRange
        
        if range.length > 0 {
            applyMutable { mutable in
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
            }
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
            applyMutable { mutable in
                mutable.enumerateAttribute(.underlineStyle, in: range, options: []) { value, subRange, _ in
                    let current = (value as? Int) ?? 0
                    if current == 0 {
                        mutable.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: subRange)
                    } else {
                        mutable.removeAttribute(.underlineStyle, range: subRange)
                    }
                }
            }
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
            applyMutable { mutable in
                mutable.addAttribute(.font, value: headerFont, range: range)
            }
        } else {
            tv.typingAttributes[.font] = headerFont
            onTextChange?(tv.attributedText)
        }
    }
}
