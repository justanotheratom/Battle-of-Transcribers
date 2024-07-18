import AVFoundation

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

    func convert(from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            print("Failed to create audio converter")
            return nil
        }
        
        let inputFrameCount = AVAudioFrameCount(self.frameLength)
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(inputFrameCount) * ratio)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCapacity) else {
            print("Failed to create output buffer")
            return nil
        }
        
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return self
        }
        
        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if status == .error {
            print("Conversion failed: \(error?.localizedDescription ?? "unknown error")")
            return nil
        }
        
        return outputBuffer
    }
}
