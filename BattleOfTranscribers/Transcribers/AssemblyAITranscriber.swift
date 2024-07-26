import Foundation
import Starscream
import AVFoundation

class AssemblyAITranscriber: TranscriberBase, WebSocketDelegate {
    
    private let requestCounter = IncrementingCounter()
    private var startTime = CFAbsoluteTimeGetCurrent()
    private var lastDuration: CFAbsoluteTime = 0
    private var socket: WebSocket?
    private var authToken: String?
    private var isConnected = false

    override func queueBuffers(buffers: [AVAudioPCMBuffer]) {
        _ = self.requestCounter.next()
        startTime = CFAbsoluteTimeGetCurrent()
        let int16Data = AVAudioPCMBuffer.mergeSamples(buffers)[0]
        let audioData = Data(bytes: int16Data, count: int16Data.count * MemoryLayout<Int16>.size)
        
        if isConnected {
            let base64Audio = audioData.base64EncodedString()
            let message: [String: Any] = [
                "audio_data": base64Audio,
                "message_type": "AudioData"
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: message),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                socket?.write(string: jsonString)
                print("Sent audio data message of length: \(jsonString.count)")
            } else {
                print("Failed to create audio data message")
            }
        } else {
            print("WebSocket not connected. Cannot send audio data.")
        }
    }
    
    override func startRecording() {
        print("Starting recording process...")
        getAuthToken { [weak self] token in
            guard let self = self else { return }
            if let token = token {
                print("Auth token received successfully")
                self.authToken = token
                self.connectToAssemblyAI()
            } else {
                print("Failed to get auth token")
            }
        }
    }

    private func getAuthToken(completion: @escaping (String?) -> Void) {
        guard let apiKey = super.config.apiKey else {
            print("API key is missing")
            completion(nil)
            return
        }
        
        let url = URL(string: "https://api.assemblyai.com/v2/realtime/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = ["expires_in": 3600] // Token expires in 1 hour
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        print("Requesting auth token...")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error fetching token: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid response")
                completion(nil)
                return
            }
            
            print("Token request status code: \(httpResponse.statusCode)")
            
            guard let data = data else {
                print("No data received")
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let token = json["token"] as? String {
                        print("Token received successfully")
                        completion(token)
                    } else {
                        print("Token not found in response")
                        print("Response: \(json)")
                        completion(nil)
                    }
                } else {
                    print("Invalid JSON response")
                    completion(nil)
                }
            } catch {
                print("Error parsing token response: \(error.localizedDescription)")
                completion(nil)
            }
        }.resume()
    }

    private func connectToAssemblyAI() {
        guard let authToken = authToken else {
            print("No auth token available")
            return
        }
        
        let baseUrlString = "wss://api.assemblyai.com/v2/realtime/ws"
        guard var urlComponents = URLComponents(string: baseUrlString) else {
            print("Invalid URL")
            return
        }
        
        // Add the documented parameters to the URL
        urlComponents.queryItems = [
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "token", value: authToken),
            URLQueryItem(name: "encoding", value: "pcm_s16le")
        ]
        
        guard let url = urlComponents.url else {
            print("Failed to create URL with parameters")
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5 // Set a reasonable timeout

        print("Connecting to AssemblyAI WebSocket with URL: \(url.absoluteString)")
        socket = WebSocket(request: request)
        socket?.delegate = self
        socket?.connect()
    }

    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .connected(let headers):
            print("WebSocket connected successfully")
            print("Connected headers: \(headers)")
            isConnected = true
        case .disconnected(let reason, let code):
            print("WebSocket disconnected with reason: \(reason), code: \(code)")
            isConnected = false
        case .text(let text):
            print("Received text: \(text)")
            processTranscription(jsonString: text)
        case .binary(let data):
            print("Received binary data of length: \(data.count)")
        case .pong(let data):
            if let data = data {
                print("Received pong with data of length: \(data.count)")
            } else {
                print("Received pong")
            }
        case .ping(let data):
            if let data = data {
                print("Received ping with data of length: \(data.count)")
            } else {
                print("Received ping")
            }
        case .error(let error):
            print("WebSocket error: \(error?.localizedDescription ?? "Unknown error")")
            isConnected = false
        case .viabilityChanged(let isViable):
            print("WebSocket viability changed: \(isViable)")
        case .reconnectSuggested(let shouldReconnect):
            print("WebSocket reconnect suggested: \(shouldReconnect)")
        case .cancelled:
            print("WebSocket cancelled")
            isConnected = false
        case .peerClosed:
            print("WebSocket peer closed")
            isConnected = false
        }
    }

    private func processTranscription(jsonString: String) {
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("Failed to convert JSON string to data")
            return
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
                print("Received JSON: \(json)")
                
                if let msgType = json["message_type"] as? String {
                    if msgType == "FinalTranscript",
                       let transcript = json["text"] as? String {
                        print("Received final transcript: \(transcript)")
                        updateTranscription(transcript)
                    } else if msgType == "PartialTranscript" {
                        print("Received partial transcript")
                    } else {
                        print("Received message of type: \(msgType)")
                    }
                } else {
                    print("Message type not found in JSON")
                }
            }
        } catch {
            print("Error parsing JSON: \(error.localizedDescription)")
        }
    }
    
    private func updateTranscription(_ transcript: String) {
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
            print("Updated transcription: \(self.state.transcription)")
        }
    }
}
