import AVFoundation
import Combine

class AudioTranscriptionViewModel: ObservableObject {
    @Published var transcribers: [TranscriberBase] = []
    @Published var isRecording: Bool = false
    
    private var configs: [TranscriberConfig]
    private var audioEngine: AVAudioEngine!

    private let targetSampleRate: Double = 16000
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                             sampleRate: 16000,
                                             channels: 1,
                                             interleaved: false)!

    private let batchSize = 5
    private var batchedBuffers: [AVAudioPCMBuffer] = []
    private let batchQueue = DispatchQueue(label: "com.transcriber.batchQueue")

    private let callbackNumberCounter = IncrementingCounter()

    init(initialConfigs: [TranscriberConfig]) {
        configs = initialConfigs
        setupAudioSession()
        prepareAudioEngine()
        updateTranscribers(with: initialConfigs)
    }
    
    func updateTranscribers(with configs: [TranscriberConfig]) {
        self.configs = configs
        self.transcribers = configs.filter { $0.isSelected }.compactMap { config in
            createTranscriber(for: config)
        }
    }

    private func createTranscriber(for config: TranscriberConfig) -> TranscriberBase? {
        switch config.name {
        case .iOS:
            return iOSTranscriber(config: config)
        case .Deepgram:
            return DeepgramTranscriber(config: config)
        case .Groq, .OpenAI:
            return OpenAICompatibleTranscriber(config: config, audioFormat: targetFormat)
        }
    }

    public func clearState() {
        updateTranscribers(with: configs)
    }

    private func setupAudioSession() {
        do {
            // Note: .playAndRecord is used here instead of .record because it
            // was found through experimentation that with .record, .notifyOthersOnDeactivation
            // was not having the intended effect.
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error.localizedDescription)")
        }
    }

    private func prepareAudioEngine() {
        audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let hardwareSampleRate = inputFormat.sampleRate
        let bufferSize = AVAudioFrameCount(hardwareSampleRate * 0.5) // 500ms worth of data

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            
            if let convertedBuffer = convert(buffer: buffer, from: inputFormat, to: targetFormat) {
                self.batchQueue.async {
                    self.batchedBuffers.append(convertedBuffer)
                    
                    if self.batchedBuffers.count >= self.batchSize {
                        let buffers = self.batchedBuffers
                        self.batchedBuffers = []
                        for transcriber in self.transcribers {
                            transcriber.queueBuffers(buffers: buffers)
                        }
                    }
                }
            } else {
                print("Conversion failed")
            }
        }
        audioEngine.prepare()
    }
    
    func convert(buffer inputBuffer: AVAudioPCMBuffer, from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            print("Failed to create audio converter")
            return nil
        }
        
        let inputFrameCount = AVAudioFrameCount(inputBuffer.frameLength)
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(inputFrameCount) * ratio)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCapacity) else {
            print("Failed to create output buffer")
            return nil
        }
        
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }
        
        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if status == .error {
            print("Conversion failed: \(error?.localizedDescription ?? "unknown error")")
            return nil
        }
        
        return outputBuffer
    }

    func startRecording() {
        Task {
            guard let audioEngine = audioEngine else { return }
            
            do {
//                let startTime = CFAbsoluteTimeGetCurrent()
                try audioEngine.start()
//                let endTime = CFAbsoluteTimeGetCurrent()
                
//                let duration = endTime - startTime
//                print("audioEngine.start() took \(duration) seconds")
                
                for transcriber in transcribers {
                    transcriber.startRecording()
                }
                
                DispatchQueue.main.async {
                    self.isRecording = true
                }
            } catch {
                print("Failed to start audio engine: \(error.localizedDescription)")
            }
        }
    }
    
    func stopRecording() {
        audioEngine.stop()
        try! AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
        batchQueue.sync {
            if !batchedBuffers.isEmpty {
                let remainingBuffers = self.batchedBuffers
                self.batchedBuffers = []
                for transcriber in self.transcribers {
                    transcriber.queueBuffers(buffers: remainingBuffers)
                }
            }
        }
    }
}

extension AVAudioPCMBuffer {
    static func merge(buffers: [AVAudioPCMBuffer]) -> AVAudioPCMBuffer? {
        guard !buffers.isEmpty else { return nil }
        
        // Ensure all buffers have the same format
        let format = buffers[0].format
        guard buffers.allSatisfy({ $0.format == format }) else {
            print("Error: All buffers must have the same audio format")
            return nil
        }
        
        // Calculate total frame count
        let totalFrameCount = buffers.reduce(0) { $0 + $1.frameLength }
        
        // Create a new buffer with the total frame count
        guard let mergedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrameCount) else {
            print("Error: Could not create merged buffer")
            return nil
        }
        
        // Append data from each buffer
        var offset: AVAudioFrameCount = 0
        for buffer in buffers {
            if format.isInterleaved {
                if let src = buffer.floatChannelData, let dst = mergedBuffer.floatChannelData {
                    for channel in 0..<Int(format.channelCount) {
                        memcpy(dst[channel] + Int(offset),
                               src[channel],
                               Int(buffer.frameLength) * MemoryLayout<Float>.size)
                    }
                }
            } else {
                if let src = buffer.int16ChannelData, let dst = mergedBuffer.int16ChannelData {
                    for channel in 0..<Int(format.channelCount) {
                        memcpy(dst[channel] + Int(offset),
                               src[channel],
                               Int(buffer.frameLength) * MemoryLayout<Int16>.size)
                    }
                }
            }
            offset += buffer.frameLength
        }
        
        mergedBuffer.frameLength = totalFrameCount
        return mergedBuffer
    }
    
    static func mergeSamples(_ buffers: [AVAudioPCMBuffer]) -> [[Int16]] {
        var mergedSamples: [[Int16]] = []
        
        for buffer in buffers {
            guard let int16ChannelData = buffer.int16ChannelData else {
                print("Warning: Buffer does not contain int16 data. Skipping.")
                continue
            }
            
            let channelCount = Int(buffer.format.channelCount)
            let frameLength = Int(buffer.frameLength)
            
            while mergedSamples.count < channelCount {
                mergedSamples.append([])
            }
            
            for channel in 0..<channelCount {
                mergedSamples[channel].append(contentsOf: Array(UnsafeBufferPointer(start: int16ChannelData[channel], count: frameLength)))
            }
        }
        
        return mergedSamples
    }
}
