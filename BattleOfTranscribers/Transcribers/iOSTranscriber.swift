
import Speech

class iOSTranscriber: TranscriberBase {
    
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer()
    private let requestCounter = IncrementingCounter()
    private var startTime = CFAbsoluteTimeGetCurrent()
    private var lastDuration: CFAbsoluteTime = 0

    override init(config: TranscriberConfig)  {
        super.init(config: config)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            fatalError("Could not create recognition request")
        }
        recognitionRequest.shouldReportPartialResults = true

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
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
                    self.state.transcription = result.bestTranscription.formattedString
                }
            }
        }
    }

    override func queueBuffer(buffer: AVAudioPCMBuffer) {
        _ = self.requestCounter.next()
        startTime = CFAbsoluteTimeGetCurrent()
        self.recognitionRequest?.append(buffer)
    }
}
