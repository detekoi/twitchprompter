import SwiftUI
import Combine

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
        currentPrompt = prompt
    }
}