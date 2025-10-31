import Foundation
import WhisperKit

final class WhisperLocalManager {
    static let shared = WhisperLocalManager()
    
    private init() {}
    
    func transcribeAudio(
        audioURL: URL,
        model: String = "medium",
        language: String? = "ru", // Опционально, чтобы можно было использовать автоопределение
        format: String = "text",
        progress: @escaping (Double) -> Void = { _ in }
    ) async throws -> String {
        
        print("TRANSCRIPTION: Запуск для \(audioURL.lastPathComponent)")
        print("TRANSCRIPTION: Модель: \(model), язык: \(language ?? "auto"), формат: \(format)")
        
        let config = WhisperKitConfig(model: model)
        
        do {
            print("TRANSCRIPTION: Инициализация...")
            let pipe = try await WhisperKit(config)
            print("TRANSCRIPTION: Модель загружена")
            
            progress(0.2)
            
            print("TRANSCRIPTION: Обработка...")
            let results: [TranscriptionResult]
            
            if let lang = language {
                // Явно указанный язык — передаем через DecodingOptions
                var options = DecodingOptions()
                options.language = lang
                results = try await pipe.transcribe(
                    audioPath: audioURL.path,
                    decodeOptions: options
                )
            } else {
                // Автоопределение языка — без language в опциях
                results = try await pipe.transcribe(audioPath: audioURL.path)
            }
            
            progress(1.0)
            
            guard let result = results.first else {
                print("TRANSCRIPTION: Нет результата")
                throw NSError(domain: "No result", code: -1)
            }
            
            print("TRANSCRIPTION: Успешно! Текст: \(result.text)")
            print("TRANSCRIPTION: Определенный язык: \(result.language)")
            
            return result.text
            
        } catch {
            print("TRANSCRIPTION: ОШИБКА: \(error.localizedDescription)")
            throw error
        }
    }
}
