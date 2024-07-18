
import Foundation
import AVFoundation
import KeychainSwift

enum TranscriberName: String, Codable, CaseIterable {
    case iOS = "iOS"
    case OpenAI = "OPENAI"
    case Deepgram = "DEEPGRAM"
    case Groq = "GROQ"
}

struct TranscriberConfig: Identifiable, Codable, Equatable {
    let id: UUID
    let name: TranscriberName
    var isSelected: Bool
    let requiresAPIKey: Bool
    let apiUrl: String?
    let modelName: String?
    
    var apiKey: String? {
        get { KeychainSwift().get(name.rawValue) }
        set {
            if let newValue = newValue {
                KeychainSwift().set(newValue, forKey: name.rawValue)
            } else {
                KeychainSwift().delete(name.rawValue)
            }
        }
    }
    
    var canBeSelected: Bool {
        !requiresAPIKey || (apiKey?.isEmpty == false)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, isSelected, requiresAPIKey, apiUrl, modelName
    }
}

protocol Transcriber {
    var name: String { get }
    var transcription: String { get }
    var requestCount: Int { get }
    var averageLatency: Double { get }
    func startRecording()
    func queueBuffers(buffers: [AVAudioPCMBuffer])
}

struct TranscriberState {
    var transcription: String = ""
    var requestCount: Int = 0
    var totalLatency: Double = 0.0
    var totalRequestSizeBytes: Int = 0
}

class TranscriberBase: Transcriber, ObservableObject {

    @Published var state = TranscriberState()
    let config: TranscriberConfig

    init(config: TranscriberConfig) {
        self.config = config
    }

    var name: String {
        config.name.rawValue
    }

    var transcription: String {
        return state.transcription
    }
    
    var requestCount: Int {
        return state.requestCount
    }
    
    var averageLatency: Double {
        state.requestCount > 0 ? state.totalLatency / Double(state.requestCount) : 0
    }
    
    var averageRequestSizeKB: Int {
        state.requestCount > 0 ? state.totalRequestSizeBytes / 1024 / state.requestCount : 0
    }

    func queueBuffers(buffers: [AVAudioPCMBuffer]) {
        fatalError("queueBuffer must be overridden by SubClass")
    }
    
    func startRecording() {
        // nothing
    }
}

