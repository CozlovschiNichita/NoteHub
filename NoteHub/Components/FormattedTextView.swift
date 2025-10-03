import SwiftUI
import UIKit

// MARK: - FormattedTextView
struct FormattedTextView: UIViewRepresentable {
    @Binding var attributedText: NSAttributedString
    @Binding var isFirstResponder: Bool
    var controller: TextViewController

    // Choose a larger default font for typing and for ranges missing a font
    private let defaultFont = UIFont.systemFont(ofSize: 18)

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = true
        tv.isSelectable = true
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.autocorrectionType = .yes
        tv.keyboardDismissMode = .interactive
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        tv.adjustsFontForContentSizeCategory = true
        tv.isScrollEnabled = true

        // Default typing font and ensure no link leaks into typing
        tv.typingAttributes[.font] = defaultFont
        tv.typingAttributes.removeValue(forKey: .link)

        // Apply default font to any ranges that lack an explicit font
        tv.attributedText = applyDefaultFontIfMissing(to: attributedText, defaultFont: defaultFont)

        // Сохраняем ссылку в контроллере
        controller.textView = tv

        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // Keep typing clean of .link; DO NOT overwrite .font here so user-chosen typing styles persist
        uiView.typingAttributes.removeValue(forKey: .link)

        // Only update if changed; also apply default font to ranges missing it
        if uiView.attributedText != attributedText {
            let previous = uiView.selectedRange
            let newText = applyDefaultFontIfMissing(to: attributedText, defaultFont: defaultFont)
            uiView.attributedText = newText
            // Clamp selection to the new text length to avoid crashes
            let length = newText.length
            let loc = max(0, min(previous.location, length))
            let maxLen = max(0, length - loc)
            let len = max(0, min(previous.length, maxLen))
            uiView.selectedRange = NSRange(location: loc, length: len)
        }

        if isFirstResponder && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFirstResponder && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // Apply default font to ranges that do not specify .font
    private func applyDefaultFontIfMissing(to attr: NSAttributedString, defaultFont: UIFont) -> NSAttributedString {
        guard attr.length > 0 else { return attr }
        let mutable = NSMutableAttributedString(attributedString: attr)
        let full = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
            if value == nil {
                mutable.addAttribute(.font, value: defaultFont, range: range)
            }
        }
        return mutable
    }

    // Coordinator — делегат UITextView
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: FormattedTextView
        init(_ parent: FormattedTextView) { self.parent = parent }

        // Prevent .link from leaking into inserted text
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Ensure typingAttributes has no .link before insertion
            textView.typingAttributes.removeValue(forKey: .link)

            // After insertion, strip any .link that may have been applied to the inserted text
            let insertLen = (text as NSString).length
            if insertLen > 0 {
                DispatchQueue.main.async { [weak self, weak textView] in
                    guard let tv = textView else { return }
                    let safeLocation = min(range.location, max(0, tv.attributedText.length - insertLen))
                    let affectedRange = NSRange(location: safeLocation, length: min(insertLen, max(0, tv.attributedText.length - safeLocation)))
                    if affectedRange.length > 0 && NSMaxRange(affectedRange) <= tv.attributedText.length {
                        tv.textStorage.removeAttribute(.link, range: affectedRange)
                        self?.parent.controller.onTextChange?(tv.attributedText)
                    }
                }
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            // Also make sure typingAttributes stays clean
            textView.typingAttributes.removeValue(forKey: .link)
            DispatchQueue.main.async {
                self.parent.attributedText = textView.attributedText ?? NSAttributedString(string: "")
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            // Keep typing attributes clean on focus
            textView.typingAttributes.removeValue(forKey: .link)
            DispatchQueue.main.async { self.parent.isFirstResponder = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            DispatchQueue.main.async { self.parent.isFirstResponder = false }
        }

        // Intercept taps on links (used for media://file)
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            if URL.scheme == "media" {
                let fileName = URL.absoluteString.replacingOccurrences(of: "media://", with: "")
                parent.controller.onImageTap?(fileName)
                return false
            }
            return true
        }

        // Backward-compatible variant for older signatures (iOS < 13)
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange) -> Bool {
            if URL.scheme == "media" {
                let fileName = URL.absoluteString.replacingOccurrences(of: "media://", with: "")
                parent.controller.onImageTap?(fileName)
                return false
            }
            return true
        }
    }
}
