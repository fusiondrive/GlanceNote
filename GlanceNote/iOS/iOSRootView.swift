// GlanceNote/iOS/iOSRootView.swift
//
// Root view for the iOS/iPadOS application.
// Presents a list of all notes and navigates to NoteEditorView on tap.

import SwiftUI
import SwiftData

struct iOSRootView: View {

    @Environment(\.modelContext) private var context

    @Query(sort: \Note.modifiedAt, order: .reverse)
    private var notes: [Note]

    @State private var selectedNote: Note?
    @State private var isCreatingNote = false

    var body: some View {
        NavigationStack {
            Group {
                if notes.isEmpty {
                    emptyState
                } else {
                    noteGrid
                }
            }
            .navigationTitle("GlanceNote")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: createNote) {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
        .sheet(item: $selectedNote) { note in
            NoteEditorSheet(note: note)
        }
    }

    // MARK: Subviews

    private var emptyState: some View {
        ContentUnavailableView(
            "No Notes",
            systemImage: "note.text",
            description: Text("Tap the pencil icon to create your first note.")
        )
    }

    private var noteGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 12) {
                ForEach(notes) { note in
                    NoteCardView(note: note, isReadOnly: false)
                        .frame(width: 155, height: 155)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                        .onTapGesture { selectedNote = note }
                        .contextMenu { noteContextMenu(for: note) }
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func noteContextMenu(for note: Note) -> some View {
        Button(role: .destructive) {
            context.delete(note)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: Actions

    private func createNote() {
        let note = Note()
        context.insert(note)
        try? context.save()
        selectedNote = note
    }
}

// MARK: - NoteEditorSheet

private struct NoteEditorSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Bindable var note: Note

    var body: some View {
        NavigationStack {
            NoteCardView(note: note)
                .ignoresSafeArea(edges: .bottom)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
