import SwiftUI

struct RadiosView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedID: RadioProfile.ID?
    @State private var draft = RadioProfile()
    @State private var isEditing = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Radio Profiles")
                    .font(.largeTitle.bold())
                Spacer()
                Text("Standalone target: \(RadioCatalog.preferredStandaloneTarget.model.rawValue)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Add") {
                    draft = RadioProfile()
                    isEditing = true
                }
                Button("Edit") {
                    guard let selectedRadio else { return }
                    draft = selectedRadio
                    isEditing = true
                }
                .disabled(selectedRadio == nil)
                Button("Delete", role: .destructive) {
                    guard selectedID != nil else { return }
                    showDeleteConfirmation = true
                }
                .disabled(selectedID == nil)
            }

            if store.sortedRadios.isEmpty {
                ContentUnavailableView(
                    "No Radio Profiles Yet",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("Start with a Radtel RT-950 Pro profile so RadMan can track native standalone support from the beginning.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(store.sortedRadios, selection: $selectedID) {
                    TableColumn("Name") { radio in
                        Text(radio.name)
                    }
                    TableColumn("Built-In Model") { radio in
                        Text(radio.builtInModel.rawValue)
                    }
                    TableColumn("Native Status") { radio in
                        Text(radio.definition.supportLevel.rawValue)
                    }
                    TableColumn("Connection") { radio in
                        Text(radio.preferredConnection.rawValue)
                    }
                    TableColumn("Serial Port") { radio in
                        Text(radio.serialPort)
                    }
                    TableColumn("Notes") { radio in
                        Text(radio.notes)
                    }
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }

            if let selectedRadio {
                let definition = selectedRadio.definition
                GroupBox("Selected Profile") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(definition.summary)
                            .foregroundStyle(.secondary)
                        RadioDetailRow(label: "Support Level", value: definition.supportLevel.rawValue)
                        RadioDetailRow(label: "Preferred Connection", value: selectedRadio.preferredConnection.rawValue)
                        RadioDetailRow(label: "Native Workflow", value: selectedRadio.preferNativeWorkflow ? "Enabled" : "Disabled")
                        RadioDetailRow(label: "Serial Port", value: selectedRadio.serialPort.isEmpty ? "Not set" : selectedRadio.serialPort)
                    }
                }
            }
        }
        .padding(24)
        .sheet(isPresented: $isEditing) {
            RadioEditorView(radio: draft) { updated in
                store.upsert(updated)
                selectedID = updated.id
            }
        }
        .confirmationDialog(
            "Delete Radio Profile?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Profile", role: .destructive) {
                guard let selectedID else { return }
                store.deleteRadios(ids: [selectedID])
                self.selectedID = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the selected radio profile from RadMan. Stored backups and clone files on disk are not deleted.")
        }
    }

    private var selectedRadio: RadioProfile? {
        guard let selectedID else { return nil }
        return store.radios.first(where: { $0.id == selectedID })
    }
}

private struct RadioEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var radio: RadioProfile
    let onSave: (RadioProfile) -> Void

    private var definition: RadioDefinition {
        RadioCatalog.definition(for: radio.builtInModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(radio.name.isEmpty ? "New Radio Profile" : "Edit Radio Profile")
                .font(.title2.bold())

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GroupBox("Profile") {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Profile Name", text: $radio.name)
                            Picker("Built-In Model", selection: $radio.builtInModel) {
                                ForEach(BuiltInRadioModel.allCases) { model in
                                    Text(model.rawValue).tag(model)
                                }
                            }
                            .onChange(of: radio.builtInModel) { _, newValue in
                                if radio.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || BuiltInRadioModel.allCases.map(\.rawValue).contains(radio.model) {
                                    radio.model = newValue.rawValue
                                }
                                if !RadioCatalog.definition(for: newValue).supportedConnections.contains(radio.preferredConnection) {
                                    radio.preferredConnection = RadioCatalog.definition(for: newValue).recommendedConnection
                                }
                            }
                            TextField("Display Model Name", text: $radio.model)
                        }
                    }

                    GroupBox("Native Support") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(definition.supportLevel.rawValue)
                                .font(.headline)
                            Text(definition.supportLevel.summary)
                                .foregroundStyle(.secondary)
                            Text(definition.summary)
                                .foregroundStyle(.secondary)

                            Picker("Preferred Connection", selection: $radio.preferredConnection) {
                                ForEach(definition.supportedConnections) { connection in
                                    Text(connection.rawValue).tag(connection)
                                }
                            }

                            Toggle("Prefer native programming when available", isOn: $radio.preferNativeWorkflow)
                            TextField("Serial Port", text: $radio.serialPort)

                            Text("Current Native Functions")
                                .font(.headline)
                            ForEach(definition.currentNativeFunctions, id: \.self) { item in
                                Text("• \(item)")
                            }

                            Text("Next Milestones")
                                .font(.headline)
                            ForEach(definition.nextNativeMilestones, id: \.self) { item in
                                Text("• \(item)")
                            }
                        }
                    }

                    GroupBox("Notes and Interop") {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Notes", text: $radio.notes)
                            ForEach(definition.compatibilityNotes, id: \.self) { note in
                                Text("• \(note)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    onSave(radio)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 560)
    }
}

private struct RadioDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(value)
        }
    }
}
