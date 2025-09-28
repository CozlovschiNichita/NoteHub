import UIKit
import Combine
import SwiftUI

class MediaManager: ObservableObject {
    static let shared = MediaManager()
    
    private let fileManager = FileManager.default
    
    // Папка для хранения медиа файлов
    private var mediaDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("Media")
    }
    
    init() {
        createMediaDirectory()
    }
    
    private func createMediaDirectory() {
        if !fileManager.fileExists(atPath: mediaDirectory.path) {
            do {
                try fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
            } catch {
                print("Error creating media directory: \(error)")
            }
        }
    }
    
    // Сохранение изображения
    func saveImage(_ image: UIImage, for noteId: UUID) -> String? {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else { return nil }
        
        let fileName = "\(noteId.uuidString)_\(Date().timeIntervalSince1970).jpg"
        let fileURL = mediaDirectory.appendingPathComponent(fileName)
        
        do {
            try imageData.write(to: fileURL)
            return fileName
        } catch {
            print("Error saving image: \(error)")
            return nil
        }
    }
    
    // Загрузка изображения
    func loadImage(named fileName: String) -> UIImage? {
        let fileURL = mediaDirectory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        
        return UIImage(contentsOfFile: fileURL.path)
    }
    
    // Удаление медиа файла
    func deleteMedia(named fileName: String) {
        let fileURL = mediaDirectory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.removeItem(at: fileURL)
            } catch {
                print("Error deleting media file: \(error)")
            }
        }
    }
    
    // Очистка медиа для заметки
    func cleanupMedia(for note: Note) {
        if let photoPath = note.photoPath {
            deleteMedia(named: photoPath)
        }
        if let voicePath = note.voicePath {
            deleteMedia(named: voicePath)
        }
        if let musicPath = note.musicPath {
            deleteMedia(named: musicPath)
        }
    }
}
