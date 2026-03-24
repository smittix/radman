import SwiftUI

struct HeardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedID: HeardFrequencyRecord.ID?
    @State private var draft = HeardFrequencyRecord()
    @State private var isEditing = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Heard Frequencies")
                .font(.largeTitle.bold())

            HStack {
                Button("Add") {
                    draft = HeardFrequencyRecord()
                    isEditing = true
                }
                Button("Edit") {
                    guard let selectedRecord else { return }
                    draft = selectedRecord
                    isEditing = true
                }
                .disabled(selectedRecord == nil)
                Button("Delete", role: .destructive) {
                    guard selectedID != nil else { return }
                    showDeleteConfirmation = true
                }
                .disabled(selectedID == nil)
            }

            Table(store.sortedHeardRecords, selection: $selectedID) {
                TableColumn("Frequency") { record in
                    Text(record.frequency)
                }
                TableColumn("Mode") { record in
                    Text(record.mode)
                }
                TableColumn("Radio") { record in
                    Text(record.radioName)
                }
                TableColumn("Source") { record in
                    Text(record.source)
                }
                TableColumn("Signal") { record in
                    Text(record.signalReport)
                }
                TableColumn("When") { record in
                    Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
        .padding(24)
        .sheet(isPresented: $isEditing) {
            HeardEditorView(record: draft, radioOptions: store.sortedRadios.map(\.name)) { updated in
                try store.upsert(updated)
                selectedID = updated.id
            }
        }
        .confirmationDialog(
            "Delete Heard Entry?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Entry", role: .destructive) {
                guard let selectedID else { return }
                store.deleteHeardRecords(ids: [selectedID])
                self.selectedID = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the selected heard-frequency log entry from RadMan.")
        }
    }

    private var selectedRecord: HeardFrequencyRecord? {
        guard let selectedID else { return nil }
        return store.heardRecords.first(where: { $0.id == selectedID })
    }
}

private struct HeardEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var record: HeardFrequencyRecord
    let radioOptions: [String]
    let onSave: (HeardFrequencyRecord) throws -> Void
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(record.frequency.isEmpty ? "New Heard Entry" : "Edit Heard Entry")
                .font(.title2.bold())

            Form {
                TextField("Frequency (MHz)", text: Binding(
                    get: { record.frequency },
                    set: { record.frequency = RadManValidationService.sanitizeMHzTyping($0) }
                ))
                TextField("Mode", text: $record.mode)
                if radioOptions.isEmpty {
                    TextField("Radio Profile", text: $record.radioName)
                } else {
                    Picker("Radio Profile", selection: $record.radioName) {
                        Text("None").tag("")
                        ForEach(radioOptions, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }
                TextField("Source", text: $record.source)
                TextField("Signal Report", text: $record.signalReport)
                TextField("Location", text: $record.location)
                TextField("Notes", text: $record.notes)
                DatePicker("Timestamp", selection: $record.timestamp)
            }

            if let errorMessage {
                RadManStatusBanner(text: errorMessage, tone: .warning)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    do {
                        try onSave(record)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 430)
    }
}
