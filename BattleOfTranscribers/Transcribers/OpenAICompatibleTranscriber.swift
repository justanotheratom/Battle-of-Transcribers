import Foundation
import AVFoundation
import Combine

class OpenAICompatibleTranscriber: TranscriberBase {

    private let writeQueue = DispatchQueue(label: "com.yourapp.audioFileWriteQueue")
    private let transcriptionQueue = DispatchQueue(label: "com.example.transcriptionQueue")
    private var isTranscribing = false
    private var isQueued = false

    private var audioBuffers: [AVAudioPCMBuffer] = []
    private let audioFormat: AVAudioFormat

    private var _requestCount = 0

    init(config: TranscriberConfig, audioFormat: AVAudioFormat) {
        self.audioFormat = audioFormat
        super.init(config: config)
    }

    override func queueBuffer(buffer: AVAudioPCMBuffer) {
        self.writeQueue.async {
            self.audioBuffers.append(buffer)
            self.queueTranscription()
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
        var request = URLRequest(url: URL(string: config.apiUrl!)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(config.apiKey!)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        
        let wavData = createWavData(from: audioBuffers)
        body.append(wavData)
        
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(config.modelName!)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("en\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        
        _requestCount += 1
        let requestNumberString = String(format: "%03d", _requestCount)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            let endTime = CFAbsoluteTimeGetCurrent()
            let duration = endTime - startTime
            
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
    
    private func createWavData(from buffers: [AVAudioPCMBuffer]) -> Data {
        var data = Data()
        
        // Calculate total frame count
        let totalFrameCount = buffers.reduce(0) { $0 + $1.frameLength }
        
        // WAV header
        data.append("RIFF".data(using: .ascii)!)
        data.append(Data(repeating: 0, count: 4)) // File size (to be filled later)
        data.append("WAVE".data(using: .ascii)!)
        
        // Format chunk
        data.append("fmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndian.data)
        data.append(UInt16(1).littleEndian.data) // Audio format (1 is PCM)
        data.append(UInt16(audioFormat.channelCount).littleEndian.data)
        data.append(UInt32(audioFormat.sampleRate).littleEndian.data)
        data.append(UInt32(audioFormat.sampleRate * 4).littleEndian.data) // Byte rate
        data.append(UInt16(4).littleEndian.data) // Block align
        data.append(UInt16(32).littleEndian.data) // Bits per sample
        
        // Data chunk
        data.append("data".data(using: .ascii)!)
        let dataSize = UInt32(totalFrameCount * 4)
        data.append(dataSize.littleEndian.data)
        
        // Audio data
        for buffer in buffers {
            if let floatChannelData = buffer.floatChannelData {
                let floatData = floatChannelData[0] // Assuming mono audio
                for i in 0..<Int(buffer.frameLength) {
                    let floatSample = floatData[i]
                    let intSample = Int32(floatSample * Float(Int32.max))
                    data.append(intSample.littleEndian.data)
                }
            }
        }
        
        // Update file size
        let fileSize = UInt32(data.count - 8)
        data.replaceSubrange(4..<8, with: fileSize.littleEndian.data)
        
        return data
    }
}

extension UInt32 {
    var data: Data {
        var int = self
        return Data(bytes: &int, count: MemoryLayout<UInt32>.size)
    }
}

extension UInt16 {
    var data: Data {
        var int = self
        return Data(bytes: &int, count: MemoryLayout<UInt16>.size)
    }
}

extension Int32 {
    var data: Data {
        var int = self
        return Data(bytes: &int, count: MemoryLayout<Int32>.size)
    }
}
