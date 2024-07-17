import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("SELECT TRANSCRIBERS (MAX 3)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                ) {
                    ForEach(viewModel.transcribers) { transcriber in
                        TranscriberRow(viewModel: viewModel, transcriber: transcriber)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Settings")
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
        }
    }
}

struct TranscriberRow: View {
    @ObservedObject var viewModel: SettingsViewModel
    let transcriber: TranscriberConfig
    @State private var apiKey: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(transcriber.name.rawValue)
                    .font(.headline)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { transcriber.isSelected },
                    set: { _ in viewModel.toggleSelection(for: transcriber) }
                ))
                .labelsHidden()
                .disabled(!canToggle)
                .opacity(canToggle ? 1 : 0.5)
            }

            if transcriber.requiresAPIKey {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        SecureField("Paste API Key", text: $apiKey)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: apiKey) { _, newValue in
                                viewModel.updateAPIKey(for: transcriber, newKey: newValue)
                            }
                        
                        Button(action: {
                            pasteAPIKey()
                        }) {
                            Image(systemName: "doc.on.clipboard")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    
                    if apiKey.isEmpty {
                        Text("API key required to enable")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            apiKey = transcriber.apiKey ?? ""
        }
    }
    
    private var canToggle: Bool {
        if transcriber.requiresAPIKey {
            return !apiKey.isEmpty && (viewModel.selectedCount < 3 || transcriber.isSelected)
        } else {
            return viewModel.selectedCount < 3 || transcriber.isSelected
        }
    }
    
    private func pasteAPIKey() {
        if let pastedString = UIPasteboard.general.string {
            apiKey = pastedString
            viewModel.updateAPIKey(for: transcriber, newKey: pastedString)
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(viewModel: SettingsViewModel())
    }
}
