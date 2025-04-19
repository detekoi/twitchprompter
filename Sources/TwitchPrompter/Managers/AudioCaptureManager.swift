import Foundation
import AVFoundation

@MainActor
protocol AudioCaptureDelegate: AnyObject {
    func didCaptureAudioBuffer(_ audioData: Data)
}

class AudioCaptureManager: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    weak var delegate: AudioCaptureDelegate?
    let source: String
    
    private var captureSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private let captureQueue = DispatchQueue(label: "audio.capture.queue")
    private var audioRecorder: AVAudioRecorder?
    private var audioTimer: Timer?
    private let audioInterval: TimeInterval = 5.0 // Send audio every 5 seconds
    
    init(source: String, delegate: AudioCaptureDelegate) {
        self.source = source
        self.delegate = delegate
        super.init()
    }
    
    func startCapture() {
        // For simplicity, we'll just use a timer to periodically send audio data
        // In a real application, you'd use AVCaptureSession for continuous capture
        setupAudioRecorder()
        
        audioTimer = Timer.scheduledTimer(withTimeInterval: audioInterval, repeats: true) { [weak self] _ in
            self?.captureAndSendAudio()
        }
        audioTimer?.fire() // Start immediately
    }
    
    func stopCapture() {
        audioTimer?.invalidate()
        audioTimer = nil
        audioRecorder?.stop()
        captureSession?.stopRunning()
        captureSession = nil
    }
    
    private func setupAudioRecorder() {
        // Configure for Gemini Live API: Raw 16 bit PCM audio at 16kHz little-endian
        let audioSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,  // 16kHz as required by Gemini
            AVNumberOfChannelsKey: 1,   // Mono audio
            AVLinearPCMBitDepthKey: 16, // 16-bit samples
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, // Little-endian as required
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("audio_buffer.wav")
        
        do {
            audioRecorder = try AVAudioRecorder(url: tempFile, settings: audioSettings)
            audioRecorder?.prepareToRecord()
        } catch {
            print("Error setting up audio recorder: \(error)")
        }
    }
    
    private func captureAndSendAudio() {
        // This is a simplified approach - in a real app, you'd implement proper audio capture
        // For demonstration purposes, we'll just create mock audio data
        
        // In a real app, you'd:
        // 1. Use AVCaptureSession to capture high-quality audio
        // 2. Process the audio buffers to ensure they're in a compatible format
        // 3. Send the properly formatted audio data to Gemini
        
        // For now, we'll just generate dummy data to demonstrate the API integration
        let dummyAudioData = generateDummyAudioData()
        
        // Use main thread for delegate calls
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didCaptureAudioBuffer(dummyAudioData)
        }
    }
    
    private func generateDummyAudioData() -> Data {
        // In a real implementation, you'd return actual recorded audio
        // For demo purposes, just create a small data buffer
        var buffer = Data(count: 1024)
        for i in 0..<buffer.count {
            buffer[i] = UInt8.random(in: 0...255)
        }
        return buffer
    }
    
    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Convert CMSampleBuffer to Data
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        
        let length = CMBlockBufferGetDataLength(blockBuffer)
        var data = Data(count: length)
        
        data.withUnsafeMutableBytes { rawBufferPointer in
            var lengthAtOffset: Int = 0
            var totalLength: Int = 0
            var pointer: UnsafeMutablePointer<Int8>?
            
            // Correct parameter labels for CMBlockBufferGetDataPointer
            CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: &lengthAtOffset,
                totalLengthOut: &totalLength,
                dataPointerOut: &pointer
            )
            
            if let source = pointer {
                let bufferPointer = UnsafeRawBufferPointer(start: source, count: length)
                rawBufferPointer.copyMemory(from: bufferPointer)
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didCaptureAudioBuffer(data)
        }
    }
}