import SwiftUI
import CoreData
import UIKit

struct NotesListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Note.createdAt, ascending: false)],
        animation: .default
    )
    private var notes: FetchedResults<Note>

    @State private var selectedNote: Note?
    @State private var showingNewNote = false

    // Share sheet state
    @State private var isPresentingShare = false
    @State private var shareItems: [Any] = []

    // Computed, in-memory sorted list: pinned first, then by createdAt desc
    private var sortedNotes: [Note] {
        notes.sorted { a, b in
            let ap = isPinned(a)
            let bp = isPinned(b)
            if ap != bp { return ap && !bp }
            let ad = a.createdAt ?? .distantPast
            let bd = b.createdAt ?? .distantPast
            return ad > bd
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedNotes) { note in
                    NavigationLink(value: note) {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                // Title (left) + time (right)
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    HStack(spacing: 6) {
                                        if isPinned(note) {
                                            Image(systemName: "pin.fill")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                        Text(displayTitle(for: note))
                                            .font(.headline)
                                            .lineLimit(1)
                                            .layoutPriority(1) // lower than time
                                    }

                                    Spacer()

                                    if let date = note.createdAt {
                                        Text(formatShortTimestamp(date))
                                            .font(.caption)
                                            .monospacedDigit()
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .layoutPriority(2) // keep visible
                                    }
                                }

                                // Secondary line: body preview OR media info OR voice OR (fallback) date
                                if let preview = bodyPreview(for: note), !preview.isEmpty {
                                    Text(preview)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                } else if let mediaInfo = photoInfo(for: note) {
                                    Text(mediaInfo.label)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                } else if hasVoice(for: note) {
                                    Text("Voice memo")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                } else if let date = note.createdAt {
                                    Text(formatDate(date))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            // Trailing thumbnail if there are photos
                            if let mediaInfo = photoInfo(for: note),
                               let thumbName = mediaInfo.firstFileName,
                               let uiImage = MediaManager.shared.loadThumbnail(named: thumbName) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 38, height: 38)
                                    .clipped()
                                    .cornerRadius(6)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    // Swipe actions: Share + Pin/Unpin + Delete
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            shareItems = buildShareItems(for: note)
                            isPresentingShare = true
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .tint(.blue)

                        Button {
                            togglePin(note)
                        } label: {
                            Label(isPinned(note) ? "Unpin" : "Pin",
                                  systemImage: isPinned(note) ? "pin.slash" : "pin")
                        }
                        .tint(.orange)

                        Button(role: .destructive) {
                            deleteNote(note)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                // Support delete in Edit Mode (maps from sorted list)
                .onDelete { offsets in
                    deleteNotesFrom(sortedNotes, offsets: offsets)
                }
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
                
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationTitle("Notes")
            .sheet(isPresented: $isPresentingShare) {
                ActivityView(activityItems: shareItems)
            }
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
            } catch {
                print("Failed to add note: \(error.localizedDescription)")
            }
        }
    }

    private func deleteNotesFrom(_ list: [Note], offsets: IndexSet) {
        withAnimation {
            offsets
                .compactMap { idx in list.indices.contains(idx) ? list[idx] : nil }
                .forEach { note in
                    MediaManager.shared.cleanupMedia(for: note)
                    viewContext.delete(note)
                }
            do {
                try viewContext.save()
            } catch {
                print("Failed to delete notes: \(error.localizedDescription)")
            }
        }
    }

    private func deleteNote(_ note: Note) {
        withAnimation {
            MediaManager.shared.cleanupMedia(for: note)
            viewContext.delete(note)
            do {
                try viewContext.save()
            } catch {
                print("Failed to delete note: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Helpers (Row content)

    private func displayTitle(for note: Note) -> String {
        let raw = note.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "New note" : raw
    }

    private func bodyPreview(for note: Note) -> String? {
        // Use saved plain text; strip attachment placeholders and trim
        let placeholder = "\u{FFFC}"
        let raw = note.text ?? ""
        let withoutPlaceholders = raw.replacingOccurrences(of: placeholder, with: "")
        let preview = withoutPlaceholders
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return preview.isEmpty ? nil : preview
    }

    private func photoInfo(for note: Note) -> (label: String, count: Int, firstFileName: String?)? {
        guard let path = note.photoPath?
                .split(separator: ",")
                .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                .filter({ !$0.isEmpty }),
              !path.isEmpty else { return nil }
        let count = path.count
        let label = count == 1 ? "1 photo" : "\(count) photos"
        return (label, count, path.first)
    }

    private func hasVoice(for note: Note) -> Bool {
        if let v = note.voicePath?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            return true
        }
        return false
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

    private func formatShortTimestamp(_ date: Date) -> String {
        // Time today, otherwise a short date
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else {
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }

    // MARK: - Pin via tags

    private func isPinned(_ note: Note) -> Bool {
        guard let tags = note.tags else { return false }
        return tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .contains("pinned")
    }

    private func togglePin(_ note: Note) {
        var parts = note.tags?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? []
        let lower = parts.map { $0.lowercased() }
        if let idx = lower.firstIndex(of: "pinned") {
            parts.remove(at: idx)
        } else {
            parts.append("pinned")
        }
        note.tags = parts.joined(separator: parts.isEmpty ? "" : ",")
        do {
            try viewContext.save()
        } catch {
            print("Failed to toggle pin: \(error.localizedDescription)")
        }
    }

    // MARK: - Share

    private func buildShareItems(for note: Note) -> [Any] {
        var items: [Any] = []

        // Compose text: title + body
        let title = displayTitle(for: note)
        let body = bodyPreview(for: note) ?? ""
        let textBlock: String = {
            if body.isEmpty { return title }
            else { return "\(title)\n\n\(body)" }
        }()
        if !textBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(textBlock)
        }

        // Images (originals if available)
        if let names = note.photoPath?
            .split(separator: ",")
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty }) {
            for name in names {
                if let image = MediaManager.shared.loadImage(named: String(name)) {
                    items.append(image)
                }
            }
        }

        // Voice (best-effort: try to resolve file URL)
        if let voice = note.voicePath?.trimmingCharacters(in: .whitespacesAndNewlines), !voice.isEmpty {
            if let url = resolveVoiceURL(fileNameOrPath: voice) {
                items.append(url)
            }
        }

        // If somehow empty, at least pass the title
        if items.isEmpty {
            items = [title]
        }

        return items
    }

    private func resolveVoiceURL(fileNameOrPath: String) -> URL? {
        // If it's already an absolute path or URL string
        if fileNameOrPath.hasPrefix("file://"), let url = URL(string: fileNameOrPath) {
            return url
        }
        let fm = FileManager.default
        // Try as absolute path
        let absolute = URL(fileURLWithPath: fileNameOrPath)
        if fm.fileExists(atPath: absolute.path) {
            return absolute
        }
        // Try Documents directory
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let candidate = docs.appendingPathComponent(fileNameOrPath)
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            // Also try Media subfolder (if you save audio there)
            let mediaCandidate = docs.appendingPathComponent("Media").appendingPathComponent(fileNameOrPath)
            if fm.fileExists(atPath: mediaCandidate.path) {
                return mediaCandidate
            }
        }
        return nil
    }
}

// MARK: - UIKit Share sheet
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        // For iPad popover safety (no-op on iPhone)
        vc.popoverPresentationController?.sourceView = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NotesListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
