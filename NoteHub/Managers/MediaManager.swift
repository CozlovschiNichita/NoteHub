import UIKit
import Combine
import SwiftUI
import CoreData

final class MediaManager {
    static let shared = MediaManager()
    
    private let fileManager = FileManager.default
    private let cache = NSCache<NSString, UIImage>() // кеш для thumbnail
    
    // Папка для хранения медиа файлов
    private var mediaDirectory: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("Media")
    }
    
    private init() {
        createMediaDirectory()
    }
    
    private func createMediaDirectory() {
        if !fileManager.fileExists(atPath: mediaDirectory.path) {
            try? fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        }
    }
    
    /// Сохраняем оригинал и создаём thumbnail
    /// Возвращает имена: (original, thumbnail)
    func saveImage(_ image: UIImage, for noteId: UUID) -> (original: String, thumbnail: String)? {
        // 1️⃣ Сохраняем оригинал
        let originalFileName = "\(noteId.uuidString)_\(UUID().uuidString).jpg"
        let originalURL = mediaDirectory.appendingPathComponent(originalFileName)
        guard let originalData = image.jpegData(compressionQuality: 0.9) else { return nil }
        
        do {
            try originalData.write(to: originalURL)
        } catch {
            print("Failed to save original image: \(error)")
            return nil
        }
        
        // 2️⃣ Создаём thumbnail
        guard let thumbImage = image.scaled(toWidth: 300),
              let thumbData = thumbImage.jpegData(compressionQuality: 0.8) else {
            return (originalFileName, originalFileName)
        }
        
        let thumbnailFileName = "\(noteId.uuidString)_thumb_\(UUID().uuidString).jpg"
        let thumbnailURL = mediaDirectory.appendingPathComponent(thumbnailFileName)
        
        do {
            try thumbData.write(to: thumbnailURL)
            cache.setObject(thumbImage, forKey: thumbnailFileName as NSString)
            return (originalFileName, thumbnailFileName)
        } catch {
            print("Failed to save thumbnail: \(error)")
            return (originalFileName, originalFileName)
        }
    }
    
    /// Загружаем thumbnail из кеша или с диска
    func loadThumbnail(named fileName: String) -> UIImage? {
        if let cached = cache.object(forKey: fileName as NSString) {
            return cached
        }
        
        let url = mediaDirectory.appendingPathComponent(fileName)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        
        let thumb = image.scaled(toWidth: 300) ?? image
        cache.setObject(thumb, forKey: fileName as NSString)
        return thumb
    }
    
    /// Загружаем оригинал
    func loadImage(named fileName: String) -> UIImage? {
        let url = mediaDirectory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
    
    /// Удаляем медиа файл и убираем из кеша
    func deleteMedia(named fileName: String) {
        let url = mediaDirectory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
        cache.removeObject(forKey: fileName as NSString)
    }
    
    /// Удаляем все медиа, связанные с заметкой:
    /// - Имена из note.photoPath (через запятую)
    /// - Любые файлы в каталоге, начинающиеся с префикса UUID заметки (включая thumbnail'ы)
    func cleanupMedia(for note: Note) {
        // 1) Удаляем то, что явно указано в photoPath
        if let photoPath = note.photoPath {
            let names = photoPath
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for name in names {
                deleteMedia(named: String(name))
            }
        }
        
        // 2) Дополнительно удаляем любые файлы, связанные с note.id (оригиналы и thumbnail'ы)
        if let idString = note.id?.uuidString {
            if let files = try? fileManager.contentsOfDirectory(atPath: mediaDirectory.path) {
                for file in files where file.hasPrefix(idString + "_") {
                    deleteMedia(named: file)
                }
            }
        }
    }
}

// MARK: - UIImage scaling
extension UIImage {
    func scaled(toWidth width: CGFloat) -> UIImage? {
        let oldWidth = self.size.width
        let scaleFactor = width / oldWidth
        let newHeight = self.size.height * scaleFactor
        let newWidth = oldWidth * scaleFactor
        let scale: CGFloat
        if let screen = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.screen {
            scale = screen.scale
        } else {
            scale = 1.0
        }

        UIGraphicsBeginImageContextWithOptions(CGSize(width: newWidth, height: newHeight), false, scale)
        self.draw(in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage
    }
}
