import SwiftUI
import CoreData

struct NotesListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Note.createdAt, ascending: false)],
        animation: .default
    )
    private var notes: FetchedResults<Note>

    @State private var selectedNote: Note?
    @State private var showingNewNote = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(notes) { note in
                    NavigationLink(value: note) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title?.isEmpty == false ? note.title! : "Untitled")
                                .font(.headline)
                                .lineLimit(1)
                            
                            Text(note.text?.isEmpty == false ? note.text! : "No content")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                            
                            if let date = note.createdAt {
                                Text(formatDate(date))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete(perform: deleteNotes)
            }
            .navigationDestination(for: Note.self) { note in
                NoteDetailView(note: note, startEditing: false)
            }
            .navigationDestination(isPresented: $showingNewNote) {
                if let newNote = selectedNote {
                    NoteDetailView(note: newNote, startEditing: true)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: addNote) {
                        Label("Add Note", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Notes")
        }
    }

    private func addNote() {
        withAnimation {
            let newNote = Note(context: viewContext)
            newNote.id = UUID()
            newNote.createdAt = Date()
            newNote.title = ""
            newNote.text = ""
            newNote.textData = try? NSKeyedArchiver.archivedData(
                withRootObject: NSAttributedString(string: ""),
                requiringSecureCoding: false
            )
            
            do {
                try viewContext.save()
                selectedNote = newNote
                showingNewNote = true
                print("Note added successfully")
            } catch {
                print("Failed to add note: \(error.localizedDescription)")
            }
        }
    }

    private func deleteNotes(offsets: IndexSet) {
        withAnimation {
            offsets.map { notes[$0] }.forEach { note in
                MediaManager.shared.cleanupMedia(for: note)
                viewContext.delete(note)
            }
            
            do {
                try viewContext.save()
                print("Notes deleted successfully")
            } catch {
                print("Failed to delete notes: \(error.localizedDescription)")
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return formatter.string(from: date)
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}

#Preview {
    NotesListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
