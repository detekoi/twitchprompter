import SwiftUI
import Combine
import Foundation

@MainActor
class AppViewModel: ObservableObject {
    @Published var twitchChannel: String = ""
    @Published var twitchConnected: Bool = false

    @Published var apiKey: String = ""
    @Published var selectedVideoSource: String = ""
    @Published var availableVideoSources: [String] = []
    @Published var selectedAudioSource: String = ""
    @Published var availableAudioSources: [String] = []

    @Published var isStreaming: Bool = false
    @Published var currentPrompt: String = "No prompt yet"
    @Published var messageHistory: [String] = []
    @Published var cumulativeText: String = ""
    private let maxHistoryItems = 10
    private let maxCumulativeLength = 2000 // Limit total cumulative text length

    private var screenCaptureManager: ScreenCaptureManager?
    private var audioCaptureManager: AudioCaptureManager?
    private var chatManager: ChatManager?
    private var geminiClient: GeminiAPIClient?

    func toggleTwitchConnection() {
        if twitchConnected {
            disconnectTwitch()
        } else {
            connectTwitch()
        }
    }

    func connectTwitch() {
        // TODO: Implement OAuth flow
        twitchConnected = true
    }

    func disconnectTwitch() {
        // TODO: Disconnect from Twitch
        twitchConnected = false
    }

    func loadApiKey() {
        // Load API key from UserDefaults for now 
        // In a production app, this should use the Keychain
        if let savedApiKey = UserDefaults.standard.string(forKey: "geminiApiKey") {
            apiKey = savedApiKey
        }
    }
    
    func saveApiKey() {
        // Save API key to UserDefaults for now
        // In a production app, this should use the Keychain
        UserDefaults.standard.set(apiKey, forKey: "geminiApiKey")
    }

    func discoverSources() {
        // TODO: Query ScreenCaptureKit and audio devices
        availableVideoSources = ["Display 1", "Application Window"]
        selectedVideoSource = availableVideoSources.first ?? ""
        availableAudioSources = ["Default Microphone", "System Audio"]
        selectedAudioSource = availableAudioSources.first ?? ""
    }

    func startStreaming() {
        guard twitchConnected else { return }
        isStreaming = true

        screenCaptureManager = ScreenCaptureManager(source: selectedVideoSource, delegate: self)
        audioCaptureManager = AudioCaptureManager(source: selectedAudioSource, delegate: self)
        chatManager = ChatManager(channel: twitchChannel, delegate: self)
        geminiClient = GeminiAPIClient(apiKey: apiKey, delegate: self)

        screenCaptureManager?.startCapture()
        audioCaptureManager?.startCapture()
        chatManager?.connect()
        geminiClient?.connect()

        // Provide an initial prompt so the UI updates immediately
        currentPrompt = "🎉 Prompter started for \(twitchChannel)!"
    }

    func stopStreaming() {
        isStreaming = false
        screenCaptureManager?.stopCapture()
        audioCaptureManager?.stopCapture()
        chatManager?.disconnect()
        geminiClient?.disconnect()
    }
}

extension AppViewModel: ScreenCaptureDelegate {
    func didCaptureVideoFrame(_ frameData: Data) {
        geminiClient?.sendVideoFrame(frameData)
    }
}

extension AppViewModel: AudioCaptureDelegate {
    func didCaptureAudioBuffer(_ audioData: Data) {
        geminiClient?.sendAudio(audioData)
    }
}

extension AppViewModel: ChatMessageDelegate {
    func didReceiveChatMessage(username: String, message: String) {
        geminiClient?.sendChatMessage(username, message)
    }
}

extension AppViewModel: GeminiClientDelegate {
    func didReceivePrompt(_ prompt: String) {
        // Process the prompt for better readability
        let processedPrompt = formatPromptForDisplay(prompt)
        
        // Update the current prompt for single-prompt display
        currentPrompt = processedPrompt
        
        // Add to message history with timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        let timestamp = dateFormatter.string(from: Date())
        
        let formattedMessage = "[\(timestamp)] \(processedPrompt)"
        messageHistory.insert(formattedMessage, at: 0)
        
        // Keep history at a reasonable size
        if messageHistory.count > maxHistoryItems {
            messageHistory.removeLast()
        }
        
        // Add to cumulative text as continuous flow
        if !cumulativeText.isEmpty {
            cumulativeText += " \(processedPrompt)"
        } else {
            cumulativeText = processedPrompt
        }
        
        // Keep cumulative text at a reasonable size
        if cumulativeText.count > maxCumulativeLength {
            // Try to find a sentence boundary to trim from
            if let rangePeriod = cumulativeText.range(of: ". ", options: .backwards, range: cumulativeText.startIndex..<cumulativeText.index(cumulativeText.endIndex, offsetBy: -maxCumulativeLength/2)) {
                cumulativeText.removeSubrange(cumulativeText.startIndex..<rangePeriod.upperBound)
            } else {
                // Fallback if no good break point found
                cumulativeText = String(cumulativeText.suffix(maxCumulativeLength))
            }
        }
    }
    
    // Helper function to format prompts for better readability
    private func formatPromptForDisplay(_ prompt: String) -> String {
        // First, clean up any potential newlines or excessive spaces
        var cleanedPrompt = prompt.replacingOccurrences(of: "\n", with: " ")
        while cleanedPrompt.contains("  ") {
            cleanedPrompt = cleanedPrompt.replacingOccurrences(of: "  ", with: " ")
        }
        
        // Break at sentence boundaries
        let sentences = cleanedPrompt.components(separatedBy: ". ")
        let formattedSentences = sentences.map { $0.trimmingCharacters(in: .whitespaces) }
        
        // Join with period and space, ensuring proper sentence formatting
        let formatted = formattedSentences.enumerated().map { index, sentence in
            // Check if sentence already ends with punctuation
            let hasPunctuation = sentence.last?.isPunctuation ?? false
            // Don't add period if it's the last sentence and it already has punctuation
            if index == sentences.count - 1 && hasPunctuation {
                return sentence
            } else if index == sentences.count - 1 {
                return "\(sentence)"
            } else {
                return "\(sentence)."
            }
        }.joined(separator: " ")
        
        return formatted
    }
}