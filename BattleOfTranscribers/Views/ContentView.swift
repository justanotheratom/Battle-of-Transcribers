import SwiftUI

struct ContentView: View {
    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var audioViewModel: AudioTranscriptionViewModel
    @State private var showSettings = false

    init() {
        let settingsVM = SettingsViewModel()
        _settingsViewModel = StateObject(wrappedValue: settingsVM)
        _audioViewModel = StateObject(wrappedValue: AudioTranscriptionViewModel(initialConfigs: settingsVM.transcribers))
    }

    var body: some View {
        NavigationStack {
            VStack {
                if audioViewModel.transcribers.isEmpty {
                    emptyStateView
                } else {
                    VStack(spacing: 10) {
                        ForEach(audioViewModel.transcribers, id: \.name) { transcriber in
                            TranscriberView(viewModel: transcriber)
                        }
                    }
                    actionButtons
                        .padding()
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Battle of Transcribers")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showSettings = true
                    }) {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: settingsViewModel)
        }
        .onChange(of: settingsViewModel.transcribers) { _, newValue in
            audioViewModel.updateTranscribers(with: newValue)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "text.quote")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text("No Transcribers selected")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Select up to 3 Transcribers from Settings.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                showSettings = true
            }) {
                Text("Open Settings")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
    }
    
    var actionButtons: some View {
        let columns = [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ]
        
        return LazyVGrid(columns: columns, content: {
            Color.clear
            
            Button(action: {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                
                if audioViewModel.isRecording {
                    audioViewModel.stopRecording()
                } else {
                    audioViewModel.startRecording()
                }
            }) {
                Image(systemName: audioViewModel.isRecording ? "stop.circle" : "record.circle")
                    .foregroundStyle(audioViewModel.isRecording ? .red : .blue)
                    .font(.system(size: 50))
                    .scaleEffect(audioViewModel.isRecording ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: audioViewModel.isRecording)
                    .opacity(audioViewModel.isRecording ? 1.0 : 0.7)
            }
            .scaleEffect(audioViewModel.isRecording ? 1.1 : 1.0)
            .animation(audioViewModel.isRecording ? Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: audioViewModel.isRecording)
            
            HStack {
                Spacer()
                VStack {
                    Spacer()
                    Button(action: {
                        audioViewModel.clearState()
                    }) {
                        Image(systemName: "eraser.line.dashed")
                            .foregroundStyle(
                                shouldEnableEraseButton ? .red : .gray
                            )
                    }
                    .disabled(!shouldEnableEraseButton)
                }
            }
            .padding(.trailing)
            .padding(.trailing)
            .padding(.bottom)
        })
    }
    
    private var shouldEnableEraseButton: Bool {
        !audioViewModel.isRecording && audioViewModel.transcribers.contains { !$0.transcription.isEmpty }
    }
}

struct TranscriberView: View {
    @ObservedObject var viewModel: TranscriberBase

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            transcriptionView
            bottomRow
        }
        .padding(10)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
        .frame(maxHeight: .infinity)
    }
    
    var transcriptionView: some View {
        VStack(alignment: .leading) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(viewModel.transcription)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.5), value: viewModel.transcription)
                        .id("transcriptionText")
                }
                .onChange(of: viewModel.transcription) { _, _ in
                    withAnimation {
                        proxy.scrollTo("transcriptionText", anchor: .bottom)
                    }
                }
            }
        }
    }
    
    var bottomRow: some View {
        HStack {
            VStack(alignment: .leading) {
                Spacer()
                Text(viewModel.name).font(.caption).fontWeight(.semibold)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer()
            statItem(title: "Requests", value: "\(viewModel.requestCount)")
            statItem(title: "Avg. Latency", value: "\(String(format: "%.2f", viewModel.averageLatency)) sec")
        }
    }
    
    func statItem(title: String, value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .frame(alignment: .leading)
    }
}

#Preview {
    ContentView()
}
