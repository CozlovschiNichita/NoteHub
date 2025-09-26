import SwiftUI
import CoreData

struct NotesListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Note.createdAt, ascending: false)], animation: .default)
    private var notes: FetchedResults<Note>

    // Для программной навигации к новой заметке
    @State private var isShowingNewNote: Bool = false
    @State private var newNoteID: NSManagedObjectID?

    var body: some View {
        NavigationView {
            List {
                ForEach(notes) { note in
                    NavigationLink {
                        // Открываем экран заметки как раньше (редактируем сразу)
                        NoteDetailView(note: note, startEditing: false)
                    } label: {
                        Text(note.title ?? "Untitled")
                    }
                }
                .onDelete(perform: deleteNotes)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: addNote) {
                        Label("Add Note", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Notes")
            // Скрытая навигация для новой заметки (созданной программно)
            .background(
                NavigationLink(
                    destination: Group {
                        if let id = newNoteID,
                           let created = try? viewContext.existingObject(with: id) as? Note {
                            NoteDetailView(note: created, startEditing: true)
                        } else {
                            EmptyView()
                        }
                    },
                    isActive: $isShowingNewNote
                ) {
                    EmptyView()
                }
                .hidden()
            )
        }
    }

    private func addNote() {
        withAnimation {
            let newNote = Note(context: viewContext)
            newNote.id = UUID()
            newNote.createdAt = Date()
            newNote.title = ""      // пустой заголовок по умолчанию
            newNote.text = ""       // пустой текст
            do {
                try viewContext.save()
                // сохранили — теперь откроем эту заметку в режиме редактирования
                newNoteID = newNote.objectID
                isShowingNewNote = true
                print("Note added and saved successfully")
            } catch {
                print("Failed to add note: \(error.localizedDescription)")
            }
        }
    }

    private func deleteNotes(offsets: IndexSet) {
        withAnimation {
            offsets.map { notes[$0] }.forEach(viewContext.delete)
            do {
                try viewContext.save()
                print("Note deleted successfully")
            } catch {
                print("Failed to delete note: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    NotesListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
