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
} // Close GeminiLiveMessageType enum

// MARK: - API Message Structs (Matching Live API Spec)

/// Wrapper to ensure only one top-level key per client message
struct ClientMessageWrapper<T: Codable>: Codable {
    let setup: T?
    let clientContent: T?
    // Add realtimeInput, toolResponse etc. as needed

    init(setup: T) {
        self.setup = setup
        self.clientContent = nil
    }

    init(clientContent: T) {
        self.setup = nil
        self.clientContent = clientContent
    }

    // Add other initializers as needed
}


/// Setup message structure (BidiGenerateContentSetup)
struct BidiGenerateContentSetup: Codable {
    let model: String // Format: "models/gemini-2.0-flash-live-001"
    let systemInstruction: Content? // Optional system prompt
    let generationConfig: GenerationConfig? // Optional generation config
    // Add tools, sessionResumption, etc. if needed

    struct Content: Codable {
        let parts: [Part]
    }

    struct Part: Codable {
        let text: String
    }
    
    // Define GenerationConfig based on API spec if needed
     struct GenerationConfig: Codable {
         let responseModalities: [String]? // e.g., ["TEXT", "AUDIO"]
         // Add temperature, topP, topK, maxOutputTokens etc. if needed
     }
}

/// Client content message structure (BidiGenerateContentClientContent)
struct BidiGenerateContentClientContent: Codable {
    let turns: [Turn]
    let turnComplete: Bool? // Optional, defaults to false if omitted? Check API spec.

    struct Turn: Codable {
        let role: String // "user" or "model"
        let parts: [Part]
    }

    struct Part: Codable {
        let text: String?
        let inlineData: InlineData?
        let audioData: AudioData?

        // Initializers matching the old GeminiLiveSendContentMessage.ContentPart.Part
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


// --- Old/Deprecated Structs (Can be removed later if fully replaced) ---

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

// --- Structs for Receiving Messages (Keep as is for now) ---

/// Model for received content
struct GeminiLiveReceiveContentMessage: Codable {
    let type: String // Keep type for initial decoding, but actual server messages might not have it
    let content: Content?
    let error: LiveError?
    // TODO: Adapt this based on actual BidiGenerateContentServerMessage structure
    // It likely won't have 'type'. It will have one of:
    // setupComplete, serverContent, toolCall, toolCallCancellation, usageMetadata, goAway, sessionResumptionUpdate

    struct Content: Codable {
        let role: String
        let parts: [Part]

        struct Part: Codable {
            let text: String?
        }
    }

    struct LiveError: Codable { // This might correspond to an error within serverContent or a specific error message type
        let code: Int
        let message: String
    }
}

/// Model for heartbeat responses (Likely not used in Live API)
struct GeminiLiveHeartbeatMessage: Codable {
    let type: String

    init() {
        self.type = GeminiLiveMessageType.heartbeat.rawValue
    }
}

/// Final metrics from the session (Corresponds to UsageMetadata in Live API)
struct GeminiLiveFinalMetricsMessage: Codable {
    let type: String // Keep type for initial decoding?
    let metrics: Metrics
    // TODO: Adapt based on actual UsageMetadata structure

    struct Metrics: Codable {
        let totalTokenCount: Int
        let promptTokenCount: Int
        // TODO: Add other relevant metric fields based on actual API response if needed
    }
} // Close GeminiLiveFinalMetricsMessage struct


// MARK: - Server Message Structures (Based on Live API Spec Inference)

/// Represents a message received from the server. Uses specific fields to determine message type.
struct BidiGenerateContentServerMessage: Decodable {
    let setupComplete: SetupComplete?
    let serverContent: ServerContent?
    // let toolCall: ToolCall? // Define if using tools
    // let toolCallCancellation: ToolCallCancellation? // Define if using tools
    let usageMetadata: UsageMetadata? // Corresponds to old FinalMetrics
    let goAway: GoAway?
    // let sessionResumptionUpdate: SessionResumptionUpdate? // Define if using session resumption
    let error: GeminiError? // General error structure

    // Check for specific error structure within serverContent as well
    var effectiveError: GeminiError? {
        return self.error ?? self.serverContent?.error
    }
}

struct SetupComplete: Decodable {
    // Contains confirmation details, potentially session ID etc.
    // For now, its presence indicates successful setup.
}

struct ServerContent: Decodable {
    let modelTurn: ModelTurn?
    // let inputTranscription: Transcription? // If requested
    // let outputTranscription: Transcription? // If requested
    let turnComplete: Bool?
    let error: GeminiError? // Errors specific to content processing
}

struct ModelTurn: Decodable {
    let role: String // Should be "model"
    let parts: [Part]

    struct Part: Decodable {
        let text: String?
        // let inlineData: InlineData? // For audio responses
        // Add other part types if needed (e.g., executableCode)

        // struct InlineData: Decodable {
        //     let mimeType: String
        //     let data: String // Base64 encoded
        // }
    }
}

// struct Transcription: Decodable {
//     let text: String?
// }

struct UsageMetadata: Decodable { // Replaces GeminiLiveFinalMetricsMessage
    let totalTokenCount: Int?
    let promptTokenCount: Int?
    // Add candidatesTokenCount, etc.
}

struct GoAway: Decodable {
    let reason: String? // e.g., "SESSION_EXPIRED"
    let message: String?
}

struct GeminiError: Decodable {
    let code: Int?
    let message: String
    // Add details if provided
}


// MARK: - Delegate Protocol

/// Delegate for receiving prompts from the Gemini Live API; methods are invoked on the main actor.
@MainActor
protocol GeminiClientDelegate: AnyObject {
    /// Called when the Gemini API returns a new prompt.
    func didReceivePrompt(_ prompt: String)
}

// MARK: - Client Implementation

class GeminiAPIClient {
    weak var delegate: GeminiClientDelegate?
    let apiKey: String
    // Using the specific WebSocket endpoint from the Google AI Live API documentation
    private let liveAPIEndpoint = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

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
        // Construct Google AI Live API URL with API key
        let wsURLString = "\(liveAPIEndpoint)?key=\(apiKey)"

        guard let wsURL = URL(string: wsURLString) else {
            print("Error: Invalid WebSocket URL (Google AI Live): \(wsURLString)")
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


        // Create the BidiGenerateContentSetup message
        let modelName = "models/gemini-2.0-flash-live-preview-04-09" // Use the model specified in Live API docs
        let systemInstruction = BidiGenerateContentSetup.Content(parts: [BidiGenerateContentSetup.Part(text: systemPrompt)])
        let generationConfig = BidiGenerateContentSetup.GenerationConfig(responseModalities: ["TEXT"]) // Match old config

        let setupPayload = BidiGenerateContentSetup(
            model: modelName,
            systemInstruction: systemInstruction,
            generationConfig: generationConfig
            // Add tools etc. here if needed
        )

        // Wrap the setup payload in the ClientMessageWrapper
        let messageToSend = ClientMessageWrapper(setup: setupPayload)

        do {
            let encoder = JSONEncoder()
            // encoder.outputFormatting = .prettyPrinted // Optional: for debugging
            let data = try encoder.encode(messageToSend)
            if let jsonString = String(data: data, encoding: .utf8) {
                 print("Sending Setup Message: \(jsonString)")
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
        guard let data = text.data(using: .utf8) else {
            print("Error: Could not convert incoming text to data.")
            return
        }

        do {
            let decoder = JSONDecoder()
            let serverMessage = try decoder.decode(BidiGenerateContentServerMessage.self, from: data)

            // --- Handle different message types ---

            // Check for Errors first
            if let error = serverMessage.effectiveError {
                print("Received Gemini API Error: \(error.code ?? 0) - \(error.message)")
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.didReceivePrompt("API Error: \(error.message)")
                    // Consider disconnecting or specific error handling
                }
                // Potentially close connection or stop processing based on error type
                 if error.code != nil { // Assume fatal errors have codes? Adjust as needed.
                     self.ws?.close(code: .internalServerError)
                 }
                return // Stop processing this message if it's an error
            }

            // Setup Complete
            if serverMessage.setupComplete != nil {
                print("Gemini API Setup Complete.")
                // Potentially set a flag like `isSetupComplete = true` if needed elsewhere
            }

            // Server Content (Model Response)
            if let content = serverMessage.serverContent, let modelTurn = content.modelTurn {
                // Aggregate text parts
                let responseText = modelTurn.parts.compactMap { $0.text }.joined()
                if !responseText.isEmpty {
                    // Append to buffer or handle directly
                    // For simplicity now, update delegate immediately if turn is complete or text exists
                     print("Received model text: \(responseText)")
                     DispatchQueue.main.async { [weak self] in
                         self?.delegate?.didReceivePrompt(responseText)
                     }
                }
                // Handle audio parts (inlineData) if needed
                
                if content.turnComplete == true {
                    print("Model turn complete.")
                    // Clear buffer, finalize response processing etc.
                }
            }

            // Usage Metadata
            if let metadata = serverMessage.usageMetadata {
                print("Received Usage Metadata: Tokens - \(metadata.totalTokenCount ?? 0)")
                // Handle final metrics
            }

            // Go Away (Session ending)
            if let goAway = serverMessage.goAway {
                print("Received Go Away: \(goAway.reason ?? "Unknown") - \(goAway.message ?? "No details")")
                // Prepare for disconnection
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.didReceivePrompt("Session ending: \(goAway.message ?? goAway.reason ?? "")")
                }
                self.ws?.close(code: .goingAway)
            }

            // Handle other message types (ToolCall, SessionResumptionUpdate) if implemented

        } catch {
            print("Error decoding incoming WebSocket message: \(error)")
            print("Raw message data: \(text)")
            // Handle decoding error, maybe the structure is wrong or message is unexpected
            DispatchQueue.main.async { [weak self] in
                 self?.delegate?.didReceivePrompt("Error processing server message.")
            }
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

    // MARK: - Content Sending

    /// Sends content parts to the Gemini API.
    /// - Parameters:
    ///   - parts: The content parts to send.
    ///   - turnComplete: Whether this message completes the user's turn and expects a response. Defaults to `false`.
    private func sendContentMessage(_ parts: [BidiGenerateContentClientContent.Part], turnComplete: Bool = false) {
         // **Strict Check:** Ensure websocket exists AND isConnected flag is true.
         guard let websocket = ws, isConnected else {
             print("Attempted to send content, but WebSocket is not connected or ready.")
             return
         }

         // Create the BidiGenerateContentClientContent message
         let turn = BidiGenerateContentClientContent.Turn(role: "user", parts: parts)
         // Set turnComplete based on the parameter. false for streaming, true when expecting a reply.
         let clientContentPayload = BidiGenerateContentClientContent(turns: [turn], turnComplete: turnComplete)

         // Wrap the clientContent payload
         let messageToSend = ClientMessageWrapper(clientContent: clientContentPayload)

         do {
             let encoder = JSONEncoder()
             // encoder.outputFormatting = .prettyPrinted // Optional: for debugging
             let data = try encoder.encode(messageToSend)
             if let jsonString = String(data: data, encoding: .utf8) {
                 print("Sending Client Content Message: \(jsonString.prefix(500))...") // Log more for debugging
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
            // Take the most recent frame
            if let latestFrame = self.pendingFrames.last {
                // Use the new BidiGenerateContentClientContent.Part structure
                let part = BidiGenerateContentClientContent.Part(imageData: latestFrame)
                // Send video frame data without marking the turn as complete
                self.sendContentMessage([part], turnComplete: false)
            }
            // Clear pending frames after processing
            self.pendingFrames.removeAll()
        }
    }
    
    func sendAudio(_ data: Data) {
        // Process audio data - ensure it's 16kHz 16-bit PCM for Live API
        // Send using the Live API structure
        // Note: GeminiMessagePart is for REST, need GeminiLiveSendContentMessage.ContentPart.Part
        // Ensure responseModalities in GenerationConfig includes "AUDIO" if you expect audio back
        // Ensure audioConfig in GenerationConfig is set if sending audio (Need to add AudioConfig to BidiGenerateContentSetup.GenerationConfig if needed)
        let part = BidiGenerateContentClientContent.Part(audioData: data)
        // Send audio data without marking the turn as complete
        sendContentMessage([part], turnComplete: false)
        // Also consider sending a text part if needed, e.g.,
        // let textPart = BidiGenerateContentClientContent.Part(text: "[Sending audio chunk]")
        // sendContentMessage([part, textPart], turnComplete: false) // Still false if just accompanying audio
    }
    
    func sendChatMessage(_ username: String, _ message: String) {
        let chatText = "\(username): \(message)"
        // Use the new BidiGenerateContentClientContent.Part structure
        let part = BidiGenerateContentClientContent.Part(text: "Chat message: \(chatText)")
        // Send chat message and mark the turn as complete to get a response
        sendContentMessage([part], turnComplete: true)
    }
}
