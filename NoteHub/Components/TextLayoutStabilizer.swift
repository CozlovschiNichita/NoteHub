import UIKit

/// Stabilizes caret and scroll around textStorage mutations to avoid jumpiness with attachments.
final class TextLayoutStabilizer {
    weak var textView: UITextView?

    init(textView: UITextView) {
        self.textView = textView
    }

    /// Executes a mutation against textStorage while freezing selection/offset, then restores them
    /// after the layout pass. Optionally moves caret to a target range.
    func performMutation(stabilizeTo targetSelection: NSRange? = nil,
                         mutation: () -> Void) {
        guard let tv = textView else { return }

        // Snapshot selection and offset
        let originalSelection = tv.selectedRange
        let originalOffset = tv.contentOffset
        let originalTransform = tv.transform

        // Temporarily disable animations and layout updates
        tv.layoutIfNeeded()
        
        tv.textStorage.beginEditing()
        mutation()
        tv.textStorage.endEditing()

        let desired = targetSelection ?? originalSelection

        // Use more reliable approach with delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard let self, let tv = self.textView else { return }

            // Restore transformation to prevent animations
            tv.transform = CGAffineTransform(scaleX: 0.999, y: 0.999)
            
            let length = tv.attributedText.length
            let loc = max(0, min(desired.location, length))
            let maxLen = max(0, length - loc)
            let len = max(0, min(desired.length, maxLen))
            tv.selectedRange = NSRange(location: loc, length: len)

            // Restore normal transformation
            DispatchQueue.main.async {
                tv.transform = .identity
            }
            
            self.scrollCaretIntoViewIfNeeded(textView: tv, fallbackOffset: originalOffset)
        }
    }

    private func scrollCaretIntoViewIfNeeded(textView tv: UITextView, fallbackOffset: CGPoint) {
        guard let start = tv.position(from: tv.beginningOfDocument, offset: tv.selectedRange.location) else { return }
        let caret = tv.caretRect(for: start)

        let visibleRect = CGRect(origin: tv.contentOffset, size: tv.bounds.size)
            .insetBy(dx: 0, dy: tv.contentInset.top + tv.contentInset.bottom)

        let margin: CGFloat = 24 // Increased margin for better visibility
        let expandedVisible = visibleRect.insetBy(dx: 0, dy: -margin)
        
        if expandedVisible.contains(caret) { return }

        var newOffset = tv.contentOffset
        if caret.minY < visibleRect.minY {
            newOffset.y = max(0, caret.minY - tv.textContainerInset.top - margin)
        } else if caret.maxY > visibleRect.maxY {
            newOffset.y = min(tv.contentSize.height - tv.bounds.height, caret.maxY - tv.bounds.height + tv.textContainerInset.bottom + margin)
        } else {
            newOffset = fallbackOffset
        }
        
        // Use without animation for stability
        UIView.performWithoutAnimation {
            tv.setContentOffset(newOffset, animated: false)
        }
    }
}
