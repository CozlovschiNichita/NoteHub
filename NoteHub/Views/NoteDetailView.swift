import SwiftUI
import CoreData

// MARK: - NoteDetailView
struct NoteDetailView: View {
    @ObservedObject var note: Note
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var editedTitle: String = ""
    @State private var editedText: NSAttributedString = NSAttributedString(string: "")
    
    @State private var textController = TextViewController()
    @State private var isEditorFocused: Bool = false
    var startEditing: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            TextField("Title", text: $editedTitle)
                .font(.title)
                .padding(.horizontal)
                .padding(.top, 8)
            
            Divider()
            
            FormattedTextView(attributedText: $editedText,
                              isFirstResponder: $isEditorFocused,
                              controller: textController)
                .padding(.horizontal)
                .frame(maxHeight: .infinity)
                .background(Color(UIColor.systemBackground))
            
            if isEditorFocused {
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        FormatButton(systemImage: "bold") {
                            textController.toggleTrait(.traitBold)
                        }
                        FormatButton(systemImage: "italic") {
                            textController.toggleTrait(.traitItalic)
                        }
                        FormatButton(systemImage: "underline") {
                            textController.toggleUnderline()
                        }
                        Menu {
                            Button("H1") { textController.makeHeader(level: 1) }
                            Button("H2") { textController.makeHeader(level: 2) }
                            Button("H3") { textController.makeHeader(level: 3) }
                        } label: {
                            Image(systemName: "textformat.size")
                        }
                        .padding(.horizontal)
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                    .background(VisualEffectView(effect: UIBlurEffect(style: .systemMaterial)))
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(editedTitle.isEmpty ? "" : editedTitle)
        .onAppear {
            editedTitle = note.title ?? ""
            
            // Load formatted text
            if let data = note.textData,
               let attributed = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data) {
                editedText = attributed
            } else {
                editedText = NSAttributedString(string: note.text ?? "")
            }
            
            if startEditing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    isEditorFocused = true
                }
            }
            
            // Callback для синхронизации
            textController.onTextChange = { newText in
                self.editedText = newText
            }
        }
        .onChange(of: editedText) { _ in saveNote() }
        .onChange(of: editedTitle) { _ in saveNote() }
        .onDisappear {
            if editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                editedText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                viewContext.delete(note)
                try? viewContext.save()
            } else {
                saveNote()
            }
        }
    }
    
    private func saveNote() {
        note.title = editedTitle
        note.text = editedText.string
        
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: editedText,
                                                        requiringSecureCoding: false) {
            note.textData = data
        }
        
        do {
            try viewContext.save()
            print("Note saved with attributed data")
        } catch {
            print("Failed to save: \(error.localizedDescription)")
        }
    }
}

// MARK: - FormatButton
struct FormatButton: View {
    let systemImage: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .padding(6)
        }
    }
}

// MARK: - VisualEffectView
struct VisualEffectView: UIViewRepresentable {
    let effect: UIVisualEffect?
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: effect)
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = effect
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let note = Note(context: context)
    note.title = ""
    note.text = ""
    return NavigationView { NoteDetailView(note: note, startEditing: true) }
}
