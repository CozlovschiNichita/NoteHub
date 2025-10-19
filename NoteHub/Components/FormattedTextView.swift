import SwiftUI
import UIKit

// MARK: - FormattedTextView
struct FormattedTextView: UIViewRepresentable {
    @Binding var attributedText: NSAttributedString
    @Binding var isFirstResponder: Bool
    var controller: TextViewController

    var bottomContentInset: CGFloat = 0
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

        tv.textColor = .label
        tv.typingAttributes[.font] = defaultFont
        tv.typingAttributes[.foregroundColor] = UIColor.label
        tv.typingAttributes[.paragraphStyle] = AttachmentParagraphStyle.body(for: defaultFont)
        tv.typingAttributes.removeValue(forKey: .link)

        let initial = applyDefaultFontIfMissing(to: attributedText, defaultFont: defaultFont)
        let normalized = enforceStableParagraphStyles(on: initial)

        // Mark this as an external application to avoid triggering a jump later
        context.coordinator.isApplyingExternalText = true
        tv.attributedText = normalized

        tv.contentInset.bottom = max(tv.contentInset.bottom, bottomContentInset)
        tv.verticalScrollIndicatorInsets.bottom = max(tv.verticalScrollIndicatorInsets.bottom, bottomContentInset)

        controller.textView = tv
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // Сохраняем текущие typingAttributes перед обновлением
        let currentTypingAttributes = uiView.typingAttributes
        let currentSelectedRange = uiView.selectedRange
        
        // Обновляем только если текст действительно изменился
        if uiView.attributedText != attributedText {
            uiView.attributedText = attributedText
        }
        
        // Восстанавливаем typingAttributes и выделение
        uiView.typingAttributes = currentTypingAttributes
        uiView.selectedRange = currentSelectedRange
        
        // Гарантируем чистые typingAttributes
        uiView.typingAttributes.removeValue(forKey: .link)

        if abs(uiView.contentInset.bottom - bottomContentInset) > 0.5 {
            uiView.contentInset.bottom = bottomContentInset
            uiView.verticalScrollIndicatorInsets.bottom = bottomContentInset
        }

        // Only apply from SwiftUI on safe/external updates.
        // Avoid replacing attributedText while user is actively typing (first responder) unless explicitly marked.
        if context.coordinator.isApplyingExternalText || !uiView.isFirstResponder {
            if uiView.attributedText != attributedText {
                let previous = uiView.selectedRange
                let withFont = applyDefaultFontIfMissing(to: attributedText, defaultFont: defaultFont)
                let normalized = enforceStableParagraphStyles(on: withFont)

                context.coordinator.shouldIgnoreNextTextChange = true
                UIView.performWithoutAnimation {
                    uiView.attributedText = normalized
                    let length = normalized.length
                    let loc = max(0, min(previous.location, length))
                    let maxLen = max(0, length - loc)
                    let len = max(0, min(previous.length, maxLen))
                    uiView.selectedRange = NSRange(location: loc, length: len)
                }
            }
            // Reset the external flag after applying
            context.coordinator.isApplyingExternalText = false
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

    // MARK: - Helpers
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

    private func enforceStableParagraphStyles(on attr: NSAttributedString) -> NSAttributedString {
        guard attr.length > 0 else { return attr }
        let mutable = NSMutableAttributedString(attributedString: attr)
        let full = NSRange(location: 0, length: mutable.length)
        
        // Remove old colors and apply stable paragraph styles
        mutable.removeAttribute(.foregroundColor, range: full)
        mutable.addAttribute(.foregroundColor, value: UIColor.label, range: full)
        
        // Ensure consistent paragraph styles
        let string = mutable.string as NSString
        var position = 0
        while position < mutable.length {
            let paragraphRange = string.paragraphRange(for: NSRange(location: position, length: 0))
            let hasAttachment = mutable.attribute(.attachment, at: paragraphRange.location, effectiveRange: nil) != nil
            
            let style = hasAttachment ?
                AttachmentParagraphStyle.make(for: defaultFont) :
                AttachmentParagraphStyle.body(for: defaultFont)
            
            mutable.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
            position = paragraphRange.location + paragraphRange.length
        }
        
        return mutable
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: FormattedTextView
        private var pendingTextUpdateWorkItem: DispatchWorkItem?
        var isApplyingExternalText: Bool = false
        var shouldIgnoreNextTextChange: Bool = false

        init(_ parent: FormattedTextView) { self.parent = parent }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Always update typing attributes before changes
            textView.typingAttributes[.foregroundColor] = UIColor.label
            textView.typingAttributes.removeValue(forKey: .link)
            
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !shouldIgnoreNextTextChange else {
                shouldIgnoreNextTextChange = false
                return
            }
            
            // Гарантируем, что вводимый текст не наследует link
            textView.typingAttributes.removeValue(forKey: .link)

            // Debounce pushing to SwiftUI
            pendingTextUpdateWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let tv = textView else { return }
                // During typing, we update the binding so saveNote can persist, but updateUIView will not reapply it while first responder.
                self.parent.attributedText = tv.attributedText
                self.parent.controller.onTextChange?(tv.attributedText, .other)
            }
            pendingTextUpdateWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            // Гарантируем чистые typingAttributes при начале редактирования
            textView.typingAttributes.removeValue(forKey: .link)
            
            DispatchQueue.main.async { self.parent.isFirstResponder = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            DispatchQueue.main.async { self.parent.isFirstResponder = false }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // Гарантируем, что typingAttributes не содержат link при изменении выделения
            textView.typingAttributes.removeValue(forKey: .link)
        }

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
