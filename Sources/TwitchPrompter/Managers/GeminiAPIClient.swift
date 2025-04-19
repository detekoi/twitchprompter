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
    let type: String = GeminiLiveMessageType.start.rawValue
    let session: SessionConfig
    
    init(session: SessionConfig) {
        self.session = session
    }
    
    struct SessionConfig: Codable {
        let id: String
        let model: String = "gemini-2.0-flash-live-001" // Use the Live API model
        let system: String?
        let audioConfig: AudioConfig?
        // Add response modalities if needed, e.g., ["TEXT", "AUDIO"]
        let responseModalities: [String]? = ["TEXT"] // Example: Request text responses

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
    let apiKey: String // Keep API key for now, but Vertex AI usually uses ADC.
    // Switching to Vertex AI endpoint structure based on documentation.
    private let vertexRegion = "us-central1"
    private let vertexProjectID = "ai-social-prompter"
    private var liveAPIEndpoint: String {
        // Note: Vertex AI uses v1beta1 for this API according to Python SDK example
        // Note: Model ID might need adjustment (e.g., gemini-2.0-flash-live-preview-04-09)
        "wss://\(vertexRegion)-aiplatform.googleapis.com/v1beta1/projects/\(vertexProjectID)/locations/\(vertexRegion)/publishers/google/models/gemini-2.0-flash-live-001:streamGenerateContent"
    }

    private var ws: WebSocket?
    private var elg: EventLoopGroup? = MultiThreadedEventLoopGroup.singleton // Use shared group
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
        
        // Ensure EventLoopGroup exists
        guard let eventLoopGroup = MultiThreadedEventLoopGroup.singleton as? EventLoopGroup else {
             print("Error: Could not get EventLoopGroup singleton.")
             // Handle error appropriately, maybe notify delegate
             DispatchQueue.main.async { [weak self] in
                 self?.delegate?.didReceivePrompt("Error: Could not initialize connection.")
             }
             return
         }
        self.elg = eventLoopGroup

        // Create a new session ID
        sessionId = UUID().uuidString
        // Construct Vertex AI URL - Authentication is typically handled by gcloud ADC or service account, not API key in URL
        let wsURLString = liveAPIEndpoint

        guard let wsURL = URL(string: wsURLString) else {
            print("Error: Invalid WebSocket URL (Vertex AI): \(wsURLString)")
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.didReceivePrompt("Error: Invalid API endpoint configuration.")
            }
            return
        }

        print("Connecting to WebSocket: \(wsURLString)")

        // Initiate WebSocket connection
        let connectionFuture = WebSocket.connect(to: wsURL, on: eventLoopGroup) { [weak self] websocket in
            guard let self = self else { return }
            self.ws = websocket
            self.isConnected = true
            print("WebSocket connected successfully.")

            // Send the start message
            self.sendStartMessage()

            // Set up message handling
            websocket.onText { ws, text in
                self.handleIncomingMessage(text)
            }

            // Set up close handling
            websocket.onClose.whenComplete { [weak self] result in
                self?.handleWebSocketClose(result: result)
            }
            
            // Notify successful connection
             DispatchQueue.main.async { [weak self] in
                 self?.delegate?.didReceivePrompt("Connected to Gemini Live API")
             }

            // Start the processing timer for frames (if needed for Live API)
            // Consider if frame processing logic needs adjustment for WebSocket streaming
            self.startProcessingTimer()
        }

        // Handle connection errors
        connectionFuture.whenFailure { [weak self] error in
            print("WebSocket connection failed: \(error)")
            self?.isConnected = false
            // Notify delegate about the failure
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.didReceivePrompt("Error connecting to Gemini Live API: \(error.localizedDescription)")
            }
        }
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
    // MARK: - WebSocket Message Handling

    private func sendStartMessage() {
        guard let websocket = ws else { return }

        // System prompt - Define it here or pass it during init
        let systemPrompt = "You are an assistant providing streamers with live prompts and content ideas based on their stream. Keep your suggestions concise, relevant to what's happening on screen, and engaging for viewers. Respond within 1-2 sentences and make your suggestions helpful for the streamer without being disruptive."

        let sessionConfig = GeminiLiveStartMessage.SessionConfig(
            id: sessionId,
            // model is set by default in the struct definition
            system: systemPrompt,
            audioConfig: nil // Add audio config if needed, e.g., .init(sampleRateHz: 16000)
            // responseModalities is set by default
        )
        let startMessage = GeminiLiveStartMessage(session: sessionConfig)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(startMessage)
            if let jsonString = String(data: data, encoding: .utf8) {
                 print("Sending Start Message: \(jsonString)")
                 websocket.send(jsonString)
            } else {
                 print("Error: Could not convert start message to JSON string")
            }
        } catch {
            print("Error encoding start message: \(error)")
        }
    }

    private func handleIncomingMessage(_ text: String) {
        print("Received WebSocket message: \(text.prefix(200))...")
        // TODO: Decode the message based on its 'type' field (receiveContent, heartbeat, error, etc.)
        // and call appropriate delegate methods or update internal state.
        // Example structure:
        /*
        guard let data = text.data(using: .utf8) else { return }
        do {
            let decoder = JSONDecoder()
            // Try decoding different message types based on a common field like 'type'
            if let genericMessage = try? decoder.decode([String: String].self, from: data),
               let typeString = genericMessage["type"],
               let type = GeminiLiveMessageType(rawValue: typeString) {

                switch type {
                case .receiveContent:
                    let message = try decoder.decode(GeminiLiveReceiveContentMessage.self, from: data)
                    // Process message.content or message.error
                    if let content = message.content, let text = content.parts.first?.text {
                         DispatchQueue.main.async { [weak self] in
                             self?.delegate?.didReceivePrompt(text)
                         }
                    } else if let error = message.error {
                         print("Received Live API Error: \(error.code) - \(error.message)")
                         DispatchQueue.main.async { [weak self] in
                             self?.delegate?.didReceivePrompt("Live API Error: \(error.message)")
                         }
                    }
                case .heartbeat:
                    // Handle heartbeat if necessary (e.g., respond if required by API)
                    print("Received Heartbeat")
                case .finalMetrics:
                    let message = try decoder.decode(GeminiLiveFinalMetricsMessage.self, from: data)
                    print("Received Final Metrics: \(message.metrics)")
                case .error:
                     // This might overlap with receiveContent.error, check API spec
                     print("Received explicit Error message type")
                default:
                    print("Received unhandled message type: \(typeString)")
                }
            } else {
                 print("Could not decode message type from: \(text)")
            }
        } catch {
            print("Error decoding incoming message: \(error)")
        }
        */
         // Placeholder: Forward raw message for now
         DispatchQueue.main.async { [weak self] in
             self?.delegate?.didReceivePrompt("Raw WS: \(text.prefix(100))")
         }
    }

    private func handleWebSocketClose(result: Result<Void, Error>) {
         print("WebSocket connection closed: \(result)")
         isConnected = false
         ws = nil
         stopProcessingTimer() // Stop processing frames on disconnect
         // Optionally attempt reconnection or notify delegate
         DispatchQueue.main.async { [weak self] in
             self?.delegate?.didReceivePrompt("Disconnected from Gemini Live API")
         }
    }

    // MARK: - Content Sending (Refactoring Needed)
    
    // TODO: Refactor this method to send content over WebSocket using GeminiLiveSendContentMessage
    private func sendContentMessage(_ parts: [GeminiLiveSendContentMessage.ContentPart.Part]) {
         guard let websocket = ws, isConnected else {
             print("Cannot send content, WebSocket not connected.")
             return
         }

         let contentPart = GeminiLiveSendContentMessage.ContentPart(parts: parts)
         let message = GeminiLiveSendContentMessage(content: contentPart)

         do {
             let encoder = JSONEncoder()
             let data = try encoder.encode(message)
             if let jsonString = String(data: data, encoding: .utf8) {
                 print("Sending Content Message: \(jsonString.prefix(200))...")
                 websocket.send(jsonString)
             } else {
                 print("Error: Could not convert content message to JSON string")
             }
         } catch {
             print("Error encoding content message: \(error)")
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
                // Send just the latest frame using the Live API structure
                // Note: GeminiMessagePart is for REST, need GeminiLiveSendContentMessage.ContentPart.Part
                let part = GeminiLiveSendContentMessage.ContentPart.Part(imageData: latestFrame)
                self.sendContentMessage([part])
            }
            // Clear pending frames
            self.pendingFrames.removeAll()
        }
    }
    
    func sendAudio(_ data: Data) {
        // Process audio data - ensure it's 16kHz 16-bit PCM for Live API
        // Send using the Live API structure
        // Note: GeminiMessagePart is for REST, need GeminiLiveSendContentMessage.ContentPart.Part
        // Ensure responseModalities in SessionConfig includes "AUDIO" if you expect audio back
        // Ensure audioConfig in SessionConfig is set if sending audio
        let part = GeminiLiveSendContentMessage.ContentPart.Part(audioData: data)
        sendContentMessage([part])
        // Also consider sending a text part if needed, e.g.,
        // let textPart = GeminiLiveSendContentMessage.ContentPart.Part(text: "[Sending audio chunk]")
        // sendContentMessage([part, textPart])
    }
    
    func sendChatMessage(_ username: String, _ message: String) {
        let chatText = "\(username): \(message)"
        // Send using the Live API structure
        // Note: GeminiMessagePart is for REST, need GeminiLiveSendContentMessage.ContentPart.Part
        let part = GeminiLiveSendContentMessage.ContentPart.Part(text: "Chat message: \(chatText)")
        sendContentMessage([part])
    }
}
