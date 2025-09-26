import SwiftUI
import CoreData

@main
struct NoteHubApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            NotesListView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
