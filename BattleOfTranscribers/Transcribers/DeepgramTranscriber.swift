import Foundation
import Starscream
import AVFoundation

class DeepgramTranscriber: TranscriberBase, WebSocketDelegate {
    
    private let requestCounter = IncrementingCounter()
    private var startTime = CFAbsoluteTimeGetCurrent()
    private var lastDuration: CFAbsoluteTime = 0
    private var socket: WebSocket?

    override func queueBuffers(buffers: [AVAudioPCMBuffer]) {
        _ = self.requestCounter.next()
        startTime = CFAbsoluteTimeGetCurrent()
        let int16Data = AVAudioPCMBuffer.mergeSamples(buffers)[0]
        let data = Data(bytes: int16Data, count: int16Data.count * MemoryLayout<Int16>.size)
        socket?.write(data: data)
    }
    
    override func startRecording() {
        connectToDeepgram()
        print("connectToDeepgram done")
    }

    private func connectToDeepgram() {
        let url = URL(string: "\(super.config.apiUrl!)?encoding=linear16&sample_rate=16000&channels=1&punctuate=true&smart_format=true&numerals=true")!
        var request = URLRequest(url: url)
        request.setValue("Token \(super.config.apiKey!)", forHTTPHeaderField: "Authorization")

        socket = WebSocket(request: request)
        socket?.delegate = self
        socket?.connect()
    }
    
    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .connected(_):
            print("WebSocket connected")
        case .text(let text):
            processTranscription(jsonString: text)
        case .disconnected(_, _):
            print("WebSocket disconnected")
        case .error(let error):
            print("WebSocket error: \(error?.localizedDescription ?? "Unknown error")")
        default:
            print("Unknown Websocket event: \(event)")
            break
        }
    }
    
    private func processTranscription(jsonString: String) {
        guard let jsonData = jsonString.data(using: .utf8) else { return }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
               let channel = json["channel"] as? [String: Any],
               let alternatives = channel["alternatives"] as? [[String: Any]],
               let transcript = alternatives.first?["transcript"] as? String {
                
                print("Received: \(transcript)")

                let endTime = CFAbsoluteTimeGetCurrent()
                let duration = endTime - startTime

                DispatchQueue.main.async {
                    let currentRequestCount = self.requestCounter.read()
                    if self.state.requestCount != currentRequestCount {
                        self.state.totalLatency += duration
                        self.state.requestCount = currentRequestCount
                    } else {
                        self.state.totalLatency = self.state.totalLatency - self.lastDuration + duration
                    }
                    self.lastDuration = duration
                    if self.state.transcription != "" {
                        self.state.transcription += " "
                    }
                    self.state.transcription += transcript
                }
            }
        } catch {
            print("Error parsing JSON: \(error.localizedDescription)")
        }
    }
}
