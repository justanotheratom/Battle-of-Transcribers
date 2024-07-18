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

    private let batchSize = 20
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
        let bufferSize = AVAudioFrameCount(hardwareSampleRate * 0.1) // 100ms worth of data

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }

            let convertedBuffer = buffer.convert(from: inputFormat, to: targetFormat)!

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
                for transcriber in self.transcribers {
                    transcriber.queueBuffers(buffers: remainingBuffers)
                }
            }
        }
    }
}
