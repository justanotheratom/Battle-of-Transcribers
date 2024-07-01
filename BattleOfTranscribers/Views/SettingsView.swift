
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Select Transcribers (Max 3)")) {
                    ForEach(viewModel.transcribers) { transcriber in
                        TranscriberRow(viewModel: viewModel, transcriber: transcriber)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(transcriber.name.rawValue)
                    .font(.headline)
                Spacer()
                Image(systemName: transcriber.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(
                        transcriber.canBeSelected
                        ?
                            transcriber.isSelected
                            ?
                                .green
                            :
                            viewModel.selectedCount < 3 ? .gray : .gray.opacity(0.5)
                        :
                            .gray.opacity(0.5))
                    .onTapGesture {
                        if transcriber.canBeSelected {
                            viewModel.toggleSelection(for: transcriber)
                        }
                    }
            }

            if transcriber.requiresAPIKey {
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Key")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        TextField("Paste API Key", text: .constant(obfuscatedAPIKey))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .disabled(true)
                        
                        Button(action: {
                            pasteAPIKey()
                        }) {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                .padding(.leading, 8)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            apiKey = transcriber.apiKey ?? ""
        }
    }
    
    private var obfuscatedAPIKey: String {
        apiKey.isEmpty ? "" : String(repeating: "•", count: 10)
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
