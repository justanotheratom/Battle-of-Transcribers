import SwiftUI

class SettingsViewModel: ObservableObject {
    @Published private(set) var transcribers: [TranscriberConfig]
    private let userDefaults = UserDefaults.standard
    private let selectedTranscribersKey = "SelectedTranscribers"
    
    var selectedCount: Int {
        transcribers.filter { $0.isSelected }.count
    }
    
    init() {
        let defaultTranscribers = [
            TranscriberConfig(
                id: UUID(),
                name: .iOS,
                isSelected: false,
                requiresAPIKey: false,
                apiUrl: nil,
                modelName: nil
            ),
            TranscriberConfig(
                id: UUID(),
                name: .Groq,
                isSelected: false,
                requiresAPIKey: true,
                apiUrl: "https://api.groq.com/openai/v1/audio/transcriptions",
                modelName: "whisper-large-v3"
            ),
            TranscriberConfig(
                id: UUID(),
                name: .OpenAI,
                isSelected: false,
                requiresAPIKey: true,
                apiUrl: "https://api.openai.com/v1/audio/transcriptions",
                modelName: "whisper-1"
            ),
            TranscriberConfig(
                id: UUID(),
                name: .Deepgram,
                isSelected: false,
                requiresAPIKey: true,
                apiUrl: "wss://api.deepgram.com/v1/listen",
                modelName: "nova-2-general"
            ),
        ]

        self.transcribers = []
        
        if let savedTranscribers = loadTranscribers() {
            self.transcribers = savedTranscribers
        } else {
            self.transcribers = defaultTranscribers
        }
    }
    
    func toggleSelection(for transcriber: TranscriberConfig) {
        if let index = transcribers.firstIndex(where: { $0.id == transcriber.id }) {
            if transcribers[index].isSelected {
                transcribers[index].isSelected = false
            } else if selectedCount < 3 && transcribers[index].canBeSelected {
                transcribers[index].isSelected = true
            }
            saveTranscribers()
        }
    }
    
    func updateAPIKey(for transcriber: TranscriberConfig, newKey: String) {
        if let index = transcribers.firstIndex(where: { $0.id == transcriber.id }) {
            transcribers[index].apiKey = newKey
            objectWillChange.send()
        }
    }
    
    private func saveTranscribers() {
        do {
            let encodedData = try JSONEncoder().encode(transcribers)
            userDefaults.set(encodedData, forKey: selectedTranscribersKey)
        } catch {
            print("Error saving transcribers: \(error)")
        }
    }
    
    private func loadTranscribers() -> [TranscriberConfig]? {
        guard let encodedData = userDefaults.data(forKey: selectedTranscribersKey) else {
            return nil
        }
        
        do {
            return try JSONDecoder().decode([TranscriberConfig].self, from: encodedData)
        } catch {
            print("Error loading transcribers: \(error)")
            return nil
        }
    }
}
