import Foundation

@MainActor
protocol ChatMessageDelegate: AnyObject {
    func didReceiveChatMessage(username: String, message: String)
}

import Foundation

/// Simple Twitch chat manager using anonymous WebSocket IRC (no OAuth)
class ChatManager {
    weak var delegate: ChatMessageDelegate?
    private let channel: String
    private var session: URLSession
    private var socket: URLSessionWebSocketTask?
    private let queue = DispatchQueue(label: "ChatManagerQueue")

    init(channel: String, delegate: ChatMessageDelegate) {
        self.channel = channel
        self.delegate = delegate
        self.session = URLSession(configuration: .default)
    }

    /// Connects to Twitch chat via anon IRC WebSocket
    func connect() {
        // Build Twitch WebSocket IRC URL (default port 443)
        // Use the same WebSocket endpoint as in the reference HTML (port included)
        // Ensure the URL has a path (URLSessionWebSocketTask requires a non-empty path)
        guard let url = URL(string: "wss://irc-ws.chat.twitch.tv:443/") else { return }
        socket = session.webSocketTask(with: url)
        socket?.resume()
        // Send IRC CAP and login commands
        sendRaw("CAP REQ :twitch.tv/tags twitch.tv/commands twitch.tv/membership")
        sendRaw("PASS SCHMOOPIIE")
        sendRaw("NICK justinfan12345")
        sendRaw("JOIN #\(channel)")
        // Start receive loop
        receiveLoop()
    }

    /// Disconnects from Twitch chat
    func disconnect() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }
    
    /// Sends a raw IRC line
    private func sendRaw(_ text: String) {
        let msg = URLSessionWebSocketTask.Message.string(text)
        socket?.send(msg) { error in
            if let err = error {
                print("[ChatManager] send error: \(err)")
            }
        }
    }

    /// Loop to receive messages continuously
    private func receiveLoop() {
        socket?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                print("[ChatManager] receive error: \(error)")
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handle(raw: text)
                default:
                    break
                }
                // Continue listening
                self.receiveLoop()
            }
        }
    }

    /// Handle raw IRC text
    private func handle(raw: String) {
        // PING/PONG keepalive
        if raw.hasPrefix("PING") {
            sendRaw("PONG :tmi.twitch.tv")
            return
        }
        // Only process PRIVMSG lines
        // Format: :username!username@username.tmi.twitch.tv PRIVMSG #channel :message
        if raw.contains("PRIVMSG #\(channel) :") {
            // Extract username (prefix before first space)
            let prefix = raw.prefix(while: { $0 != " " })
            let namePart = prefix.dropFirst().split(separator: "!").first.map(String.init) ?? ""
            // Extract message after first ' :'
            if let range = raw.range(of: "PRIVMSG #\(channel) :") {
                let msgStart = raw.index(range.upperBound, offsetBy: 0)
                let msg = String(raw[msgStart...])
                // Dispatch to main actor via delegate
                DispatchQueue.main.async {
                    self.delegate?.didReceiveChatMessage(username: namePart, message: msg)
                }
            }
        }
    }
}