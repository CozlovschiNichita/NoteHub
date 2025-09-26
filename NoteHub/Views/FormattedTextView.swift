import SwiftUI
import UIKit

// MARK: - FormattedTextView
struct FormattedTextView: UIViewRepresentable {
    @Binding var attributedText: NSAttributedString
    @Binding var isFirstResponder: Bool
    var controller: TextViewController
    
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
        controller.textView = tv
        return tv
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.attributedText != attributedText {
            let selected = uiView.selectedRange
            uiView.attributedText = attributedText
            uiView.selectedRange = selected
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
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: FormattedTextView
        init(_ parent: FormattedTextView) { self.parent = parent }
        
        func textViewDidChange(_ textView: UITextView) {
            DispatchQueue.main.async {
                self.parent.attributedText = textView.attributedText ?? NSAttributedString(string: "")
            }
        }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            DispatchQueue.main.async { self.parent.isFirstResponder = true }
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            DispatchQueue.main.async { self.parent.isFirstResponder = false }
        }
    }
}
