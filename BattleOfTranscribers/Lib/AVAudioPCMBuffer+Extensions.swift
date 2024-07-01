import AVFoundation

public extension AVAudioPCMBuffer {
    
    func append(contentsOf buffers: [AVAudioPCMBuffer]) {
        for buffer in buffers {
            append(buffer)
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        append(buffer, startingFrame: 0, frameCount: buffer.frameLength)
    }
    
    func append(_ buffer: AVAudioPCMBuffer,
                startingFrame: AVAudioFramePosition,
                frameCount: AVAudioFrameCount)
    {
        precondition(format == buffer.format, "Format mismatch")
        precondition(startingFrame + AVAudioFramePosition(frameCount) <= AVAudioFramePosition(buffer.frameLength), "Insufficient audio in buffer")
        precondition(frameLength + frameCount <= frameCapacity, "Insufficient space in buffer")
        
        let channelCount = Int(format.channelCount)
        for channel in 0..<channelCount {
            if let dstChannel = floatChannelData?[channel],
               let srcChannel = buffer.floatChannelData?[channel] {
                memcpy(dstChannel.advanced(by: stride * Int(frameLength)),
                       srcChannel.advanced(by: stride * Int(startingFrame)),
                       Int(frameCount) * stride * MemoryLayout<Float>.size)
            }
        }

        frameLength += frameCount
    }
}
