import SwiftUI

struct ContactsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedID: ContactLog.ID?
    @State private var draft = ContactLog()
    @State private var isEditing = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contacts")
                .font(.largeTitle.bold())

            HStack {
                Button("Add") {
                    draft = ContactLog()
                    isEditing = true
                }
                Button("Edit") {
                    guard let selectedContact else { return }
                    draft = selectedContact
                    isEditing = true
                }
                .disabled(selectedContact == nil)
                Button("Delete", role: .destructive) {
                    guard selectedID != nil else { return }
                    showDeleteConfirmation = true
                }
                .disabled(selectedID == nil)
            }

            Table(store.sortedContacts, selection: $selectedID) {
                TableColumn("Callsign") { contact in
                    Text(contact.callsign)
                }
                TableColumn("Name") { contact in
                    Text(contact.operatorName)
                }
                TableColumn("Frequency") { contact in
                    Text(contact.frequency)
                }
                TableColumn("Mode") { contact in
                    Text(contact.mode)
                }
                TableColumn("Radio") { contact in
                    Text(contact.radioName)
                }
                TableColumn("When") { contact in
                    Text(contact.timestamp.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
        .padding(24)
        .sheet(isPresented: $isEditing) {
            ContactEditorView(contact: draft, radioOptions: store.sortedRadios.map(\.name)) { updated in
                try store.upsert(updated)
                selectedID = updated.id
            }
        }
        .confirmationDialog(
            "Delete Contact?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Contact", role: .destructive) {
                guard let selectedID else { return }
                store.deleteContacts(ids: [selectedID])
                self.selectedID = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the selected contact log entry from RadMan.")
        }
    }

    private var selectedContact: ContactLog? {
        guard let selectedID else { return nil }
        return store.contacts.first(where: { $0.id == selectedID })
    }
}

private struct ContactEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var contact: ContactLog
    let radioOptions: [String]
    let onSave: (ContactLog) throws -> Void
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(contact.callsign.isEmpty ? "New Contact" : "Edit Contact")
                .font(.title2.bold())

            Form {
                TextField("Callsign", text: Binding(
                    get: { contact.callsign },
                    set: { contact.callsign = RadManValidationService.sanitizeASCII($0, maxLength: 12) }
                ))
                TextField("Operator Name", text: $contact.operatorName)
                TextField("Frequency (MHz)", text: Binding(
                    get: { contact.frequency },
                    set: { contact.frequency = RadManValidationService.sanitizeMHzTyping($0) }
                ))
                TextField("Mode", text: $contact.mode)
                if radioOptions.isEmpty {
                    TextField("Radio Profile", text: $contact.radioName)
                } else {
                    Picker("Radio Profile", selection: $contact.radioName) {
                        Text("None").tag("")
                        ForEach(radioOptions, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }
                TextField("Location", text: $contact.location)
                TextField("Signal Sent", text: $contact.signalSent)
                TextField("Signal Received", text: $contact.signalReceived)
                TextField("Notes", text: $contact.notes)
                DatePicker("Timestamp", selection: $contact.timestamp)
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
                        try onSave(contact)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 460)
    }
}
