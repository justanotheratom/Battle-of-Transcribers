import AVFoundation
import Combine

class AudioTranscriptionViewModel: ObservableObject {
    @Published var transcribers: [TranscriberBase] = []
    @Published var isRecording: Bool = false
    
    private var configs: [TranscriberConfig]
    private var audioEngine: AVAudioEngine!

    private let targetSampleRate: Double = 16000
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
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
        let bufferSize = AVAudioFrameCount(hardwareSampleRate * 0.4) // 400ms worth of data

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }

//            let callbackNumber = self.callbackNumberCounter.next()

            let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(targetSampleRate * 0.4)) else {
                print("Failed to create converted buffer")
                return
            }
            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            converter?.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
            
            if let error = error {
                print("Conversion error: \(error.localizedDescription)")
                return
            }
            
            self.batchQueue.async {
                self.batchedBuffers.append(convertedBuffer)
                
                if self.batchedBuffers.count >= self.batchSize {
                    let buffersToMerge = self.batchedBuffers
                    self.batchedBuffers = []
                    let totalFrameCount = buffersToMerge.reduce(0) { $0 + $1.frameLength }
                    let combinedBuffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: totalFrameCount)!
                    combinedBuffer.append(contentsOf: buffersToMerge)

                    for transcriber in self.transcribers {
                        transcriber.queueBuffer(buffer: combinedBuffer)
                    }
                }
            }
        }
        audioEngine.prepare()
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
                let totalFrameCount = remainingBuffers.reduce(0) { $0 + $1.frameLength }
                let combinedBuffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: totalFrameCount)!
                combinedBuffer.append(contentsOf: remainingBuffers)

                for transcriber in self.transcribers {
                    transcriber.queueBuffer(buffer: combinedBuffer)
                }
            }
        }
    }
}
