import SwiftUI
import CoreData

@main
struct NoteHubApp: App {
    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            NotesListView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .preferredColorScheme(appTheme.colorScheme)
        }
    }
}
