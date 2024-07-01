
import Foundation
import AVFoundation
import Combine

class OpenAICompatibleTranscriber: TranscriberBase {

    private var audioFile: AVAudioFile!
    private var audioFileURL: URL!

    private let writeQueue = DispatchQueue(label: "com.yourapp.audioFileWriteQueue")
    private let transcriptionQueue = DispatchQueue(label: "com.example.transcriptionQueue")
    private var isTranscribing = false
    private var isQueued = false

    init(config: TranscriberConfig, audioFormat: AVAudioFormat) {
        super.init(config: config)
        createOrEmptyAudioFile(audioFormat)
    }

    private var _requestCount = 0

    override func queueBuffer(buffer: AVAudioPCMBuffer) {
        self.writeQueue.async {
            try! self.audioFile.write(from: buffer)
            self.queueTranscription()
        }
    }

    private func createOrEmptyAudioFile(_ audioFormat: AVAudioFormat) {
        do {
            let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            audioFileURL = documentPath.appendingPathComponent("\(config.name).recording.wav")

            if FileManager.default.fileExists(atPath: audioFileURL.path) {
                try FileManager.default.removeItem(at: audioFileURL)
            }
            
            audioFile = try AVAudioFile(forWriting: audioFileURL, settings: audioFormat.settings)
            
            let emptyBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: 0)!
            try audioFile?.write(from: emptyBuffer)
            
        } catch {
            print("Failed to create or empty audio file: \(error.localizedDescription)")
        }
    }

    private func queueTranscription() {
        transcriptionQueue.sync {
            if isTranscribing {
                isQueued = true
            } else {
                isQueued = false
                isTranscribing = true
                transcribeAudio()
            }
        }
    }
    
    private func timestampString() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        return dateFormatter.string(from: Date())
    }

    private func transcribeAudio() {
        guard let audioData = try? Data(contentsOf: audioFileURL) else { return }

        _requestCount += 1
        let requestNumberString = String(format: "%03d", _requestCount)
//        print("\(timestampString()) : \(requestNumberString) : Audio data length: \(audioData.count)")

        var request = URLRequest(url: URL(string: config.apiUrl!)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(config.apiKey!)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(config.modelName!)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("en\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        
        let startTime = CFAbsoluteTimeGetCurrent()
//        print("\(timestampString()) : \(requestNumberString) : Sending request")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            let endTime = CFAbsoluteTimeGetCurrent()
            let duration = endTime - startTime
//            print("\(self.timestampString()) : \(requestNumberString) : Request finished: \(String(format: "%.2f", duration)) seconds")
            defer {
                self.transcriptionQueue.sync {
                    if self.isQueued {
                        self.isQueued = false
                        self.isTranscribing = true
                        self.transcribeAudio()
                    } else {
                        self.isTranscribing = false
                    }
                }
            }
            if let error = error {
                print("\(self.timestampString()) : \(requestNumberString) : Failed to send audio data: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("\(self.timestampString()) : \(requestNumberString) : Did not receive any data")
                return
            }
            
            if let jsonResponse = try? JSONSerialization.jsonObject(with: data, options: []),
               let jsonDict = jsonResponse as? [String: Any],
               let transcription = jsonDict["text"] as? String {
//                print("\(self.timestampString()) : \(requestNumberString) : Received: \(transcription)")
                DispatchQueue.main.async {
                    self.state.transcription = transcription.trimmingCharacters(in: .whitespaces)
                    self.state.requestCount = self._requestCount
                    self.state.totalLatency += duration
                }
            } else {
                print("\(self.timestampString()) : \(requestNumberString) : Received something unexpected")
                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
                   let prettyPrintedData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
                   let prettyPrintedString = String(data: prettyPrintedData, encoding: .utf8) {
                    print("\(self.timestampString()) : \(requestNumberString) : Pretty Printed Unexpected JSON Response: \(prettyPrintedString)")
                } else {
                    print("\(self.timestampString()) : \(requestNumberString) : Failed to pretty print JSON response or data is not valid JSON")
                }
            }
        }.resume()
    }
}
