import UIKit

final class MediaAttachment: NSTextAttachment {
    var fileName: String?
    
    override var image: UIImage? {
        didSet {
            // Убедимся, что bounds обновляется при изменении image
            if let image = image, bounds == .zero {
                bounds = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
            }
        }
    }
}
