import Foundation
import AVFoundation
import Combine

struct TranscriptFragment {
    var fragment: String
    var bufferCount: Int
}

class OpenAICompatibleTranscriber: TranscriberBase {

    private let transcriptionQueue = DispatchQueue(label: "com.example.transcriptionQueue")
    private var isTranscribing = false
    private var isQueued = false

    private var audioBuffers: [AVAudioPCMBuffer] = []
    private let audioFormat: AVAudioFormat

    private var _requestCount = 0
    
    private let maxTranscriptionWindow = 4
    private var fragments: [TranscriptFragment] = []
    private var prefix: String = ""

    init(config: TranscriberConfig, audioFormat: AVAudioFormat) {
        self.audioFormat = audioFormat
        super.init(config: config)
    }

    override func queueBuffers(buffers: [AVAudioPCMBuffer]) {
        transcriptionQueue.async {
            self.audioBuffers.append(contentsOf: buffers)
            if self.isTranscribing {
                self.isQueued = true
            } else {
                self.isQueued = false
                self.isTranscribing = true
                self.transcribeAudio()
            }
        }
    }
    
    private func timestampString() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        return dateFormatter.string(from: Date())
    }

    private func transcribeAudio() {
        var request = URLRequest(url: URL(string: "https://\(config.apiUrl!)/audio/transcriptions")!)
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
        body.append("\(config.speechModelName!)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("en\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(self.prefix)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        
        let secondsToTranscribe =
            Int(audioBuffers.reduce(0) { $0 + $1.frameLength })
            /
            Int(audioFormat.sampleRate)
        
        let buffersTranscribed = self.audioBuffers.count

        _requestCount += 1
        let requestNumberString = String(format: "%03d", _requestCount)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            let endTime = CFAbsoluteTimeGetCurrent()
            let duration = endTime - startTime
            var newTranscript: String? = nil
            
            defer {
                self.transcriptionQueue.sync {
                    if let newTranscript {
                        self.trimBuffers(newTranscript: newTranscript, bufferCount: buffersTranscribed)
                    }
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
//                print("Transcript: \(transcription)")
                newTranscript = sanitizeTranscript(transcription.trimmingCharacters(in: .whitespaces))
                let prefix = self.prefix
                DispatchQueue.main.async {
                    let newTranscription =
                        self.appendTranscript(
                            prefix: prefix,
                            suffix: newTranscript!
                        )
                    if !self.state.transcription.isEmpty
                        &&
                        !self.state.transcription.hasSuffix("\n")
                        &&
                        self.state.transcription == newTranscription {
                        Task {
                            let lastLine = self.extractLastLine(newTranscription)
                            if try! await isCompleteSentence(
                                lastLine,
                                apiUrl: self.config.apiUrl!,
                                apiKey: self.config.apiKey!,
                                modelName: self.config.textModelName!) {
                                if self.state.transcription == newTranscription {
                                    self.transcriptionQueue.async {
                                        self.audioBuffers = []
                                        self.fragments = []
                                        self.prefix = newTranscription + "\n----\n"
                                        DispatchQueue.main.async {
                                            self.state.transcription = self.prefix
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        self.state.transcription = newTranscription
                    }
                    self.state.requestCount = self._requestCount
                    self.state.totalLatency += duration
                    self.state.totalSecondsTranscribed += secondsToTranscribe
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
    
    private func trimBuffers(newTranscript: String, bufferCount: Int) {
        fragments.append(TranscriptFragment(fragment: newTranscript, bufferCount: bufferCount))
        if fragments.count == 1 {
            return
        }
        if fragments.count == maxTranscriptionWindow {
            let firstIsPrefixOfAll = fragments.dropFirst().allSatisfy { $0.fragment.hasPrefix(fragments[0].fragment) }
            if firstIsPrefixOfAll {
//                print("--------------------")
//                fragments.indices.forEach {
//                    print("\($0): \(fragments[$0].fragment)")
//                }
                let firstFragment = fragments[0]
                fragments.removeFirst()
                fragments.indices.forEach {
                    fragments[$0].bufferCount -= firstFragment.bufferCount
                    fragments[$0].fragment.removeFirst(firstFragment.fragment.count)
                }
                audioBuffers.removeFirst(firstFragment.bufferCount)
//                print("Prefix Befor: \(prefix)")
                prefix = appendTranscript(prefix: prefix, suffix: firstFragment.fragment)
//                print("Prefix After: \(prefix)")
            } else {
                fragments.removeFirst()
            }
        }
    }

    private func sanitizeTranscript(_ transcript: String) -> String {
        
        let fillerPhrases = Set([
            "Thank you.",
            "You",
            "you",
            "Thanks for watching!",
            "Thank you for watching!",
            "Thank you for watching.",
            ".",
            ". ."
        ])

        if fillerPhrases.contains(transcript) {
            return ""
        }
        
        return transcript
    }
    
    private func appendTranscript(prefix: String, suffix: String) -> String {

        if suffix.isEmpty {
            return prefix
        }

        if prefix.isEmpty {
            return suffix
        }
        
        if prefix.hasSuffix("\n") {
            return prefix + suffix
        }

        return prefix + " " + suffix
    }
    
    func extractLastLine(_ input: String) -> String {
        let components = input.components(separatedBy: "\n")
        return components.last ?? input
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
        data.append(UInt32(audioFormat.sampleRate * 2).littleEndian.data) // Byte rate (2 bytes per sample)
        data.append(UInt16(2).littleEndian.data) // Block align (2 bytes per sample)
        data.append(UInt16(16).littleEndian.data) // Bits per sample
        
        // Data chunk
        data.append("data".data(using: .ascii)!)
        let dataSize = UInt32(totalFrameCount * 2) // 2 bytes per sample
        data.append(dataSize.littleEndian.data)
        
        for buffer in buffers {
            let int16Data = buffer.int16ChannelData![0]
            for i in 0..<Int(buffer.frameLength) {
                let sample = int16Data[i]
                data.append(sample.littleEndian.data)
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

extension Int16 {
    var data: Data {
        var int = self
        return Data(bytes: &int, count: MemoryLayout<Int16>.size)
    }
}
