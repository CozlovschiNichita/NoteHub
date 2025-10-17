import SwiftUI
import UIKit
import PhotosUI

struct MediaPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var selectedVideoURL: URL?
    @Environment(\.dismiss) private var dismiss

    var sourceType: UIImagePickerController.SourceType

    func makeUIViewController(context: Context) -> UIViewController {
        switch sourceType {
        case .camera:
            let picker = UIImagePickerController()
            picker.delegate = context.coordinator
            picker.sourceType = .camera
            picker.mediaTypes = ["public.image"]
            picker.allowsEditing = false
            return picker
        default:
            var config = PHPickerConfiguration(photoLibrary: PHPhotoLibrary.shared())
            config.selectionLimit = 1
            config.filter = .images

            let picker = PHPickerViewController(configuration: config)
            picker.delegate = context.coordinator
            return picker
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // no-op
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate, PHPickerViewControllerDelegate {
        let parent: MediaPicker

        init(_ parent: MediaPicker) {
            self.parent = parent
        }

        // MARK: - Camera (UIImagePickerController)
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            } else if let edited = info[.editedImage] as? UIImage {
                parent.selectedImage = edited
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        // MARK: - Photo Library (PHPicker)
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let item = results.first else {
                parent.dismiss()
                return
            }

            let provider = item.itemProvider

            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                    DispatchQueue.main.async {
                        if let img = object as? UIImage {
                            self?.parent.selectedImage = img
                        } else if let error = error {
                            print("PHPicker load image error: \(error.localizedDescription)")
                        }
                        self?.parent.dismiss()
                    }
                }
            } else {
                // Как fallback можно попробовать загрузить данные как файл
                let typeIdentifier = UTType.image.identifier
                provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] data, error in
                    DispatchQueue.main.async {
                        if let data, let img = UIImage(data: data) {
                            self?.parent.selectedImage = img
                        } else if let error = error {
                            print("PHPicker load data error: \(error.localizedDescription)")
                        }
                        self?.parent.dismiss()
                    }
                }
            }
        }
    }
}
