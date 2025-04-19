import Foundation
import WebSocketKit
import NIO

/// Delegate for receiving prompts from the Gemini Live API
@MainActor
protocol GeminiClientDelegate: AnyObject {
    func didReceivePrompt(_ prompt: String)
}

/// Live API message types
enum MessageType: String {
    case setup = "setup"
    case clientContent = "clientContent"
    case setupComplete = "setupComplete"
    case serverContent = "serverContent"
    case error = "error"
}

/// Gemini Live API client implementation
class GeminiAPIClient {
    // MARK: - Properties
    
    weak var delegate: GeminiClientDelegate?
    let apiKey: String
    private let endpoint = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
    
    private var ws: WebSocket?
    private var elg: EventLoopGroup?
    private var isConnected = false
    private var pendingFrames = [Data]()
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3
    
    // Queue for processing frames
    private let processingQueue = DispatchQueue(label: "com.twitchprompter.gemini.processing")
    private let processingInterval: TimeInterval = 3.0
    private var processingTimer: Timer?
    
    // MARK: - Initialization
    
    init(apiKey: String, delegate: GeminiClientDelegate) {
        self.apiKey = apiKey
        self.delegate = delegate
    }
    
    // MARK: - Public Methods
    
    func connect() {
        guard !isConnected else { return }
        
        // If we've tried too many times, let the user know
        if reconnectAttempts >= maxReconnectAttempts {
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.didReceivePrompt("Multiple connection attempts failed. Please check API key and connectivity.")
            }
        }
        
        // Create event loop group
        elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        guard let elg = elg else { return }
        
        // Construct WebSocket URL with API key
        let wsURLString = "\(endpoint)?key=\(apiKey)"
        guard let wsURL = URL(string: wsURLString) else {
            print("Invalid WebSocket URL")
            return
        }
        
        print("Connecting to WebSocket: \(wsURLString)")
        
        // Connect to WebSocket - no timeout configuration, using default
        WebSocket.connect(to: wsURL, on: elg) { [weak self] ws in
            guard let self = self else { return }
            
            self.ws = ws
            self.isConnected = true
            self.reconnectAttempts = 0
            print("WebSocket connected successfully.")
            
            // Send initial setup message
            self.sendSetupMessage()
            
            // Configure message handlers
            ws.onText { [weak self] _, text in
                print("Received text message: \(text.prefix(100))...")
                self?.handleMessage(text)
            }
            
            ws.onBinary { [weak self] _, buffer in
                print("Received binary data: \(buffer.readableBytes) bytes")
                
                // Read binary data and convert to string
                var data = Data()
                let bytes = buffer.readableBytesView
                data.append(contentsOf: bytes)
                
                if let text = String(data: data, encoding: .utf8) {
                    print("Binary data as text: \(text.prefix(100))...")
                    self?.handleMessage(text)
                } else {
                    print("Could not decode binary data as UTF-8 text")
                }
            }
            
            ws.onPing { _, _ in
                print("Received ping")
            }
            
            ws.onPong { _, _ in
                print("Received pong")
            }
            
            // WebSocketKit doesn't have onError
            
            ws.onClose.whenComplete { [weak self] result in
                guard let self = self else { return }
                
                print("WebSocket closed: \(result)")
                self.isConnected = false
                self.ws = nil
                self.stopProcessingTimer()
                
                DispatchQueue.main.async {
                    self.delegate?.didReceivePrompt("Disconnected from Gemini API. Attempting to reconnect...")
                }
                
                // Try to reconnect after a delay
                let delay = min(pow(2.0, Double(self.reconnectAttempts)), 30.0)
                self.reconnectAttempts += 1
                
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self, !self.isConnected else { return }
                    self.connect()
                }
            }
            
            // Start processing frames
            self.startProcessingTimer()
            
            // Notify successful connection
            DispatchQueue.main.async {
                self.delegate?.didReceivePrompt("Connected to Gemini Live API")
            }
        }.whenFailure { [weak self] error in
            guard let self = self else { return }
            
            print("WebSocket connection failed: \(error)")
            self.isConnected = false
            self.reconnectAttempts += 1
            
            // Notify delegate and retry
            DispatchQueue.main.async {
                let delay = min(pow(2.0, Double(self.reconnectAttempts)), 30.0)
                self.delegate?.didReceivePrompt("Error connecting to Gemini API: \(error.localizedDescription). Retrying in \(Int(delay)) seconds...")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self, !self.isConnected else { return }
                    self.connect()
                }
            }
        }
    }
    
    func disconnect() {
        // Close the WebSocket connection
        if let ws = ws {
            ws.close().whenComplete { _ in
                print("WebSocket closed by disconnect()")
            }
        }
        
        isConnected = false
        stopProcessingTimer()
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didReceivePrompt("Disconnected from Gemini API")
        }
    }
    
    func sendVideoFrame(_ data: Data) {
        processingQueue.async { [weak self] in
            self?.pendingFrames.append(data)
        }
    }
    
    func sendAudio(_ data: Data) {
        // Currently, we'll just send a placeholder message
        sendTextMessage("[Audio input received]", turnComplete: false)
    }
    
    func sendChatMessage(_ username: String, _ message: String) {
        let chatText = "\(username): \(message)"
        sendTextMessage("Chat message: \(chatText)", turnComplete: true)
    }
    
    // MARK: - Private Methods
    
    private func startProcessingTimer() {
        processingTimer = Timer.scheduledTimer(withTimeInterval: processingInterval, repeats: true) { [weak self] _ in
            self?.processPendingFrames()
        }
    }
    
    private func stopProcessingTimer() {
        processingTimer?.invalidate()
        processingTimer = nil
    }
    
    private func processPendingFrames() {
        processingQueue.async { [weak self] in
            guard let self = self, !self.pendingFrames.isEmpty, self.isConnected else { return }
            
            // Use only the most recent frame
            if let latestFrame = self.pendingFrames.last {
                self.sendImageMessage(latestFrame)
            }
            
            self.pendingFrames.removeAll()
        }
    }
    
    private func sendSetupMessage() {
        guard let ws = ws else { return }
        
        // System prompt for streamers
        let systemPrompt = "You are an assistant providing streamers with live prompts and content ideas based on their stream. Keep your suggestions concise, relevant to what's happening on screen, and engaging for viewers. Respond within 1-2 sentences and make your suggestions helpful for the streamer without being disruptive."
        
        // Create setup message
        let setupMessage: [String: Any] = [
            "setup": [
                "model": "models/gemini-2.0-flash-live-001",
                "generationConfig": [
                    "responseModalities": ["TEXT"]
                ],
                "systemInstruction": [
                    "parts": [
                        ["text": systemPrompt]
                    ]
                ]
            ]
        ]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: setupMessage)
            if let json = String(data: data, encoding: .utf8) {
                print("Sending Setup Message: \(json)")
                ws.send(json)
            }
        } catch {
            print("Error encoding setup message: \(error)")
        }
    }
    
    private func sendTextMessage(_ text: String, turnComplete: Bool = false) {
        guard let ws = ws, isConnected else {
            print("Attempted to send text, but WebSocket is not connected")
            return
        }
        
        // Create client content message with text
        let message: [String: Any] = [
            "clientContent": [
                "turns": [
                    [
                        "role": "user",
                        "parts": [
                            ["text": text]
                        ]
                    ]
                ],
                "turnComplete": turnComplete
            ]
        ]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            if let json = String(data: data, encoding: .utf8) {
                print("Sending Text Message: \(json.prefix(100))...")
                ws.send(json)
            }
        } catch {
            print("Error encoding text message: \(error)")
        }
    }
    
    private func sendImageMessage(_ imageData: Data) {
        guard let ws = ws, isConnected else {
            print("Attempted to send image, but WebSocket is not connected")
            return
        }
        
        // Create client content message with image
        let message: [String: Any] = [
            "clientContent": [
                "turns": [
                    [
                        "role": "user",
                        "parts": [
                            [
                                "inlineData": [
                                    "mimeType": "image/jpeg",
                                    "data": imageData.base64EncodedString()
                                ]
                            ]
                        ]
                    ]
                ],
                "turnComplete": true
            ]
        ]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            if let json = String(data: data, encoding: .utf8) {
                print("Sending Image Message (truncated): \(json.prefix(100))...")
                ws.send(json)
            }
        } catch {
            print("Error encoding image message: \(error)")
        }
    }
    
    private func handleMessage(_ text: String) {
        print("Handling message: \(text)")
        
        guard let data = text.data(using: .utf8) else {
            print("Could not convert message to data")
            return
        }
        
        // Try to parse as generic JSON
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("Message keys: \(json.keys.joined(separator: ", "))")
                
                // Check for setup complete
                if json["setupComplete"] != nil {
                    print("✅ Setup complete confirmed")
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.didReceivePrompt("Gemini Live API connected successfully")
                    }
                    return
                }
                
                // Check for error
                if let error = json["error"] as? [String: Any] {
                    let code = error["code"] as? Int
                    let message = error["message"] as? String
                    print("⚠️ Error: code=\(code ?? 0), message=\(message ?? "unknown")")
                    
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.didReceivePrompt("API Error: \(message ?? "Unknown error")")
                    }
                    return
                }
                
                // Check for server content (response)
                if let content = json["serverContent"] as? [String: Any] {
                    print("Found serverContent")
                    
                    // Pretty print content for debugging
                    if let contentData = try? JSONSerialization.data(withJSONObject: content, options: .prettyPrinted),
                       let prettyContent = String(data: contentData, encoding: .utf8) {
                        print("Content: \(prettyContent)")
                    }
                    
                    if let modelTurn = content["modelTurn"] as? [String: Any],
                       let parts = modelTurn["parts"] as? [[String: Any]] {
                        
                        // Extract text from all parts
                        let texts = parts.compactMap { part in
                            part["text"] as? String
                        }
                        
                        let responseText = texts.joined()
                        if !responseText.isEmpty {
                            print("📝 Received response: \(responseText)")
                            DispatchQueue.main.async { [weak self] in
                                self?.delegate?.didReceivePrompt(responseText)
                            }
                        } else {
                            print("Response parts contained no text")
                        }
                    } else {
                        print("Could not find modelTurn or parts in serverContent")
                    }
                }
            } else {
                print("Message is not valid JSON")
            }
        } catch {
            print("JSON parsing error: \(error)")
        }
    }
}