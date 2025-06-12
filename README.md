# TwitchPrompter

A macOS application built in Swift using SwiftUI that captures screen, audio, and Twitch chat to generate live prompts using the Gemini AI API.

## Features
- Real-time screen and audio capture.
- Twitch chat integration for contextual AI prompt generation.
- Continuous prompt display with message history.
- Configurable video/audio sources and Twitch channel.
- Extensible architecture using SwiftUI, Combine, and Swift Package Manager.

## Requirements
- Swift 5.7 or later 【F:Package.swift†L1】
- macOS 13.0 (Ventura) or later 【F:Package.swift†L7】
- Xcode 14.0 or later
- A Gemini API key.
- A Twitch channel name.

## Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/<USERNAME>/social-prompter.git
   cd social-prompter
   ```
2. Fetch dependencies and build:
   ```bash
   swift build
   ```

## Usage
1. Run the app:
   ```bash
   swift run TwitchPrompter
   ```
2. In the app's Configuration view:
   - Enter your Twitch channel and connect.
   - Enter and save your Gemini API key.
   - Select the video (screen) and audio sources.
3. Click **Start Streaming** to begin streaming data to the AI and view live prompts.
4. Click **Stop Streaming** to end the capture.

## Development
Build and run commands are maintained in [CLAUDE.md](CLAUDE.md):
```bash
# Build the project
swift build
# Run the executable
swift run TwitchPrompter
# Clean build artifacts
swift package clean
# Run tests (if any)
swift test
```
【F:CLAUDE.md†L5-L9】

## Project Structure
Follows the standard Swift Package Manager layout:
```
Sources/
└── TwitchPrompter/
    ├── AppViewModel.swift
    ├── ContentView.swift
    ├── ConfigurationView.swift
    ├── PromptView.swift
    └── Managers/
        ├── AudioCaptureManager.swift
        ├── ChatManager.swift
        ├── ScreenCaptureManager.swift
        └── GeminiAPIClient.swift
```
【F:CLAUDE.md†L23-L25】【F:Package.swift†L5-L15】

## Coding Guidelines
See [CLAUDE.md](CLAUDE.md) for coding style and contribution guidelines.

## License
This project is licensed under the BSD 2-Clause "Simplified" License - see the [LICENSE](LICENSE) file for details.