import SwiftUI
import UIKit

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.bounces = true
        scrollView.backgroundColor = .clear
        scrollView.maximumZoomScale = 5.0
        scrollView.minimumZoomScale = 1.0
        scrollView.contentInsetAdjustmentBehavior = .never

        // Image view
        let imageView = UIImageView(image: image)
        imageView.isUserInteractionEnabled = true
        imageView.contentMode = .scaleAspectFit
        // Start with the image's natural size; we will fit via zoomScale
        imageView.frame = CGRect(origin: .zero, size: image.size)

        scrollView.addSubview(imageView)
        scrollView.contentSize = image.size

        context.coordinator.imageView = imageView

        // Double‑tap to zoom
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        // Initial fit
        context.coordinator.updateZoomScalesAndFit(scrollView: scrollView)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        // If the image changes (rare in this use), update and refit
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
            context.coordinator.imageView?.frame = CGRect(origin: .zero, size: image.size)
            scrollView.contentSize = image.size
        }
        // Recompute scales in case bounds changed (rotation, etc.)
        context.coordinator.updateZoomScalesAndFit(scrollView: scrollView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        private var lastBoundsSize: CGSize = .zero

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage(in: scrollView)
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            let pointInView = recognizer.location(in: imageView)

            let minScale = scrollView.minimumZoomScale
            let maxScale = scrollView.maximumZoomScale
            let current = scrollView.zoomScale

            // Toggle between fit and a closer zoom
            let targetScale = (abs(current - minScale) < 0.01) ? min(minScale * 2.0, maxScale) : minScale

            zoom(to: pointInView, scale: targetScale, in: scrollView)
        }

        func updateZoomScalesAndFit(scrollView: UIScrollView) {
            guard let imageView, imageView.bounds.width > 0, imageView.bounds.height > 0 else { return }

            let boundsSize = scrollView.bounds.size
            guard boundsSize.width > 0, boundsSize.height > 0 else { return }

            // Avoid excessive work if bounds didn’t change
            if lastBoundsSize == boundsSize, scrollView.zoomScale >= scrollView.minimumZoomScale {
                centerImage(in: scrollView)
                return
            }
            lastBoundsSize = boundsSize

            // Compute scale to fit
            let xScale = boundsSize.width / imageView.bounds.width
            let yScale = boundsSize.height / imageView.bounds.height
            let minScale = min(xScale, yScale)

            scrollView.minimumZoomScale = minScale
            scrollView.maximumZoomScale = max(minScale * 4.0, minScale) // allow zooming in
            scrollView.zoomScale = minScale

            centerImage(in: scrollView)
        }

        private func zoom(to point: CGPoint, scale: CGFloat, in scrollView: UIScrollView) {
            guard let imageView else { return }
            let boundsSize = scrollView.bounds.size

            let width = boundsSize.width / scale
            let height = boundsSize.height / scale
            let x = point.x - (width / 2.0)
            let y = point.y - (height / 2.0)

            let zoomRect = CGRect(x: x, y: y, width: width, height: height)
            scrollView.zoom(to: zoomRect, animated: true)
        }

        private func centerImage(in scrollView: UIScrollView) {
            guard let imageView else { return }
            let boundsSize = scrollView.bounds.size
            let frameToCenter = imageView.frame

            let scaledWidth = frameToCenter.size.width * scrollView.zoomScale
            let scaledHeight = frameToCenter.size.height * scrollView.zoomScale

            // Compute insets to center when content is smaller than bounds
            let horizontalInset = max(0, (boundsSize.width - scaledWidth) / 2.0)
            let verticalInset = max(0, (boundsSize.height - scaledHeight) / 2.0)

            scrollView.contentInset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
        }
    }
}
