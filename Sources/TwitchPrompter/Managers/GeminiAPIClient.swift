import Foundation
import WebSocketKit
import NIO

// MARK: - Message Models

/// Live API message types
enum GeminiLiveMessageType: String, Codable {
    case start = "start"
    case sendContent = "sendContent"
    case receiveContent = "receiveContent"
    case heartbeat = "heartbeat"
    case finalMetrics = "finalMetrics"
    case error = "error"
}

/// Message to initialize a Live API session
struct GeminiLiveStartMessage: Codable {
    let type: String
    let session: SessionConfig
    
    init(session: SessionConfig) {
        self.type = GeminiLiveMessageType.start.rawValue
        self.session = session
    }
    
    struct SessionConfig: Codable {
        let id: String
        let model: String
        let system: String?
        let audioConfig: AudioConfig?
        
        struct AudioConfig: Codable {
            let sampleRateHz: Int
            let audioEncoding: String
            
            init(sampleRateHz: Int) {
                self.sampleRateHz = sampleRateHz
                self.audioEncoding = "linear16"
            }
        }
    }
}

/// Message component that can contain text or binary data
struct GeminiMessagePart {
    let text: String?
    let inlineData: GeminiInlineData?
    
    init(text: String) {
        self.text = text
        self.inlineData = nil
    }
    
    init(data: Data, mimeType: String) {
        self.text = nil
        self.inlineData = GeminiInlineData(mimeType: mimeType, data: data.base64EncodedString())
    }
}

/// Base64 encoded data with MIME type
struct GeminiInlineData {
    let mimeType: String
    let data: String // Base64 encoded data
}

/// Message to send content to the model
struct GeminiLiveSendContentMessage: Codable {
    let type: String
    let content: ContentPart
    
    init(content: ContentPart) {
        self.type = GeminiLiveMessageType.sendContent.rawValue
        self.content = content
    }
    
    struct ContentPart: Codable {
        let role: String
        let parts: [Part]
        
        init(parts: [Part]) {
            self.role = "user"
            self.parts = parts
        }
        
        struct Part: Codable {
            let text: String?
            let inlineData: InlineData?
            let audioData: AudioData?
            
            init(text: String) {
                self.text = text
                self.inlineData = nil
                self.audioData = nil
            }
            
            init(imageData: Data) {
                self.text = nil
                self.inlineData = InlineData(
                    mimeType: "image/jpeg",
                    data: imageData.base64EncodedString()
                )
                self.audioData = nil
            }
            
            init(audioData data: Data) {
                self.text = nil
                self.inlineData = nil
                self.audioData = AudioData(data: data.base64EncodedString())
            }
        }
        
        struct InlineData: Codable {
            let mimeType: String
            let data: String // Base64-encoded data
        }
        
        struct AudioData: Codable {
            let data: String // Base64-encoded audio data
        }
    }
}

/// Model for received content
struct GeminiLiveReceiveContentMessage: Codable {
    let type: String
    let content: Content?
    let error: LiveError?
    
    struct Content: Codable {
        let role: String
        let parts: [Part]
        
        struct Part: Codable {
            let text: String?
        }
    }
    
    struct LiveError: Codable {
        let code: Int
        let message: String
    }
}

/// Model for heartbeat responses
struct GeminiLiveHeartbeatMessage: Codable {
    let type: String
    
    init() {
        self.type = GeminiLiveMessageType.heartbeat.rawValue
    }
}

/// Final metrics from the session
struct GeminiLiveFinalMetricsMessage: Codable {
    let type: String
    let metrics: Metrics
    
    struct Metrics: Codable {
        let totalTokenCount: Int
        let promptTokenCount: Int
        let responseTokenCount: Int
    }
}

// MARK: - Delegate Protocol

@MainActor
protocol GeminiClientDelegate: AnyObject {
    func didReceivePrompt(_ prompt: String)
}

// MARK: - Client Implementation

class GeminiAPIClient {
    weak var delegate: GeminiClientDelegate?
    let apiKey: String
    // Use the standard Gemini Pro model for now
    private let restEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent"
    
    private var ws: WebSocket?
    private var elg: EventLoopGroup?
    private var isConnected = false
    private var sessionId = UUID().uuidString
    private var contentBuffer = [String]()
    private var pendingFrames = [Data]()
    private var heartbeatTimer: Timer?
    
    // Queue for processing frames to avoid overloading the API
    private let processingQueue = DispatchQueue(label: "com.twitchprompter.gemini.processing")
    private let processingInterval: TimeInterval = 3.0 // Process frames every 3 seconds
    private var processingTimer: Timer?
    
    init(apiKey: String, delegate: GeminiClientDelegate) {
        self.apiKey = apiKey
        self.delegate = delegate
    }
    
    // MARK: - Connection Management
    
    func connect() {
        guard !isConnected else { return }
        
        // Create a new session ID
        sessionId = UUID().uuidString
        
        // Using HTTP request for streaming instead of direct WebSocket
        self.isConnected = true
        
        // Notify successful connection
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didReceivePrompt("Connected to Gemini API")
        }
        
        // Start the processing timer for frames
        startProcessingTimer()
    }
    
    func disconnect() {
        stopProcessingTimer()
        isConnected = false
        
        // Notify disconnection
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didReceivePrompt("Disconnected from Gemini API")
        }
    }
    
    // No heartbeat needed for HTTP-based streaming
    
    // MARK: - Processing Timer
    
    private func startProcessingTimer() {
        processingTimer = Timer.scheduledTimer(withTimeInterval: processingInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.processPendingFrames()
        }
    }
    
    private func stopProcessingTimer() {
        processingTimer?.invalidate()
        processingTimer = nil
    }
    
    // MARK: - Session Initialization
    
    // MARK: - Content Sending
    
    private func sendContentMessage(_ parts: [GeminiMessagePart]) {
        guard isConnected else { return }
        
        // Create URL request
        var urlComponents = URLComponents(string: restEndpoint)
        urlComponents?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        
        guard let url = urlComponents?.url else {
            print("Failed to create URL")
            return
        }
        
        // System prompt
        let systemPrompt = "You are an assistant providing streamers with live prompts and content ideas based on their stream. Keep your suggestions concise, relevant to what's happening on screen, and engaging for viewers. Respond within 1-2 sentences and make your suggestions helpful for the streamer without being disruptive."
        
        // Create request body
        let requestContent = [
            "contents": [
                ["role": "system", "parts": [["text": systemPrompt]]],
                ["role": "user", "parts": parts.map { part in
                    var partDict: [String: Any] = [:]
                    if let text = part.text {
                        partDict["text"] = text
                    }
                    if let inlineData = part.inlineData {
                        partDict["inlineData"] = [
                            "mimeType": inlineData.mimeType,
                            "data": inlineData.data
                        ]
                    }
                    return partDict
                }]
            ],
            "generation_config": [
                "temperature": 0.4,
                "topP": 0.95,
                "topK": 40,
                "maxOutputTokens": 1024
            ]
        ] as [String: Any]
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            // This can throw an error, so we need the try
            request.httpBody = try JSONSerialization.data(withJSONObject: requestContent)
            
            // Create and start data task
            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }
                
                // Print HTTP response info
                if let httpResponse = response as? HTTPURLResponse {
                    print("HTTP response status: \(httpResponse.statusCode)")
                    print("HTTP response headers: \(httpResponse.allHeaderFields)")
                }
                
                // Handle response error
                if let error = error {
                    print("API request failed: \(error)")
                    DispatchQueue.main.async {
                        self.delegate?.didReceivePrompt("Error from Gemini API: \(error.localizedDescription)")
                    }
                    return
                }
                
                guard let data = data else {
                    print("No data received")
                    return
                }
                
                // Parse the response
                if let responseText = String(data: data, encoding: .utf8) {
                    print("Response: \(responseText.prefix(200))...")
                    
                    do {
                        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                        
                        // Extract and process candidate content
                        if let candidates = json?["candidates"] as? [[String: Any]], 
                           let firstCandidate = candidates.first,
                           let content = firstCandidate["content"] as? [String: Any],
                           let parts = content["parts"] as? [[String: Any]],
                           let firstPart = parts.first,
                           let text = firstPart["text"] as? String {
                            
                            // Update UI with the response text
                            DispatchQueue.main.async {
                                self.delegate?.didReceivePrompt(text)
                            }
                        } else {
                            print("Could not extract text from response: \(responseText)")
                        }
                    } catch {
                        print("Failed to parse JSON: \(error)")
                    }
                }
            }
            
            task.resume()
            
        } catch let jsonError {
            // This catch block is for the JSONSerialization.data call
            print("Failed to create request body: \(jsonError)")
        }
    }
    
    // MARK: - Public Methods
    
    func sendVideoFrame(_ data: Data) {
        // Add to pending frames instead of sending immediately
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            self.pendingFrames.append(data)
        }
    }
    
    private func processPendingFrames() {
        processingQueue.async { [weak self] in
            guard let self = self, !self.pendingFrames.isEmpty, self.isConnected else { return }
            
            // Take the most recent frame
            if let latestFrame = self.pendingFrames.last {
                // Send just the latest frame to avoid overwhelming the API
                let part = GeminiMessagePart(data: latestFrame, mimeType: "image/jpeg")
                self.sendContentMessage([part])
            }
            
            // Clear pending frames
            self.pendingFrames.removeAll()
        }
    }
    
    func sendAudio(_ data: Data) {
        // Process audio data - ensure it's 16kHz 16-bit PCM
        // Note: Audio not fully supported in the standard API
        let chatMessage = GeminiMessagePart(text: "[Audio input received]")
        sendContentMessage([chatMessage])
    }
    
    func sendChatMessage(_ username: String, _ message: String) {
        let chatText = "\(username): \(message)"
        let part = GeminiMessagePart(text: "Chat message: \(chatText)")
        sendContentMessage([part])
    }
}