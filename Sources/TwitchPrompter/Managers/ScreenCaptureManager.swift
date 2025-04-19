import Foundation
import AppKit
import AVFoundation

@MainActor
protocol ScreenCaptureDelegate: AnyObject {
    func didCaptureVideoFrame(_ frameData: Data)
}

class ScreenCaptureManager {
    weak var delegate: ScreenCaptureDelegate?
    let source: String
    
    private var captureTimer: Timer?
    private let captureInterval: TimeInterval = 2.0 // Capture a frame every 2 seconds
    
    init(source: String, delegate: ScreenCaptureDelegate) {
        self.source = source
        self.delegate = delegate
    }
    
    func startCapture() {
        // Start a timer to capture frames at regular intervals
        captureTimer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { [weak self] _ in
            self?.captureFrame()
        }
        captureTimer?.fire() // Capture first frame immediately
    }
    
    func stopCapture() {
        captureTimer?.invalidate()
        captureTimer = nil
    }
    
    private func captureFrame() {
        // Basic screen capture implementation using NSScreen
        // In a production app, you would use ScreenCaptureKit for better performance
        guard let mainScreen = NSScreen.main else { return }
        
        // Create a bitmap representation of the screen
        let screenRect = mainScreen.frame
        guard let screenImage = CGWindowListCreateImage(screenRect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution) else {
            print("Failed to capture screen image")
            return
        }
        
        // Convert CGImage to NSImage
        let nsImage = NSImage(cgImage: screenImage, size: NSSize(width: screenRect.width, height: screenRect.height))
        
        // Scale down the image for Gemini API (max 1024x1024 is a common limit)
        let maxDimension: CGFloat = 1024
        let scaledImage = resizeImage(nsImage, to: maxDimension)
        
        // Convert to JPEG data
        guard let jpegData = convertToJpegData(scaledImage, quality: 0.7) else {
            print("Failed to convert image to JPEG")
            return
        }
        
        // Send to delegate on main thread
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didCaptureVideoFrame(jpegData)
        }
    }
    
    private func resizeImage(_ image: NSImage, to maxDimension: CGFloat) -> NSImage {
        let originalSize = image.size
        var newSize = originalSize
        
        if originalSize.width > maxDimension || originalSize.height > maxDimension {
            let widthRatio = maxDimension / originalSize.width
            let heightRatio = maxDimension / originalSize.height
            let ratio = min(widthRatio, heightRatio)
            
            newSize = NSSize(width: originalSize.width * ratio, height: originalSize.height * ratio)
        }
        
        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: newSize), 
                 from: NSRect(origin: .zero, size: originalSize),
                 operation: .copy, 
                 fraction: 1.0)
        
        resizedImage.unlockFocus()
        return resizedImage
    }
    
    private func convertToJpegData(_ image: NSImage, quality: CGFloat) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}