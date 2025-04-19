# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands
- Build: `swift build`
- Run: `swift run TwitchPrompter`
- Clean: `swift package clean`
- Test: `swift test`

## Code Style Guidelines
- **Imports**: Group by framework, SwiftUI first, then other Apple frameworks, then custom
- **Naming**: Use descriptive camelCase variable/property names and PascalCase for types
- **Types**: Use explicit type annotations for public APIs, infer for local variables
- **Error Handling**: Use try/catch with descriptive error types, delegate error reporting when appropriate
- **SwiftUI**: Use @MainActor for all view models, apply environmentObject for dependency injection
- **Protocols**: Define protocol interfaces before implementation classes
- **Extensions**: Organize functionality into extensions by protocol conformance
- **Code Organization**: Group related properties and methods together
- **Comments**: Limit comments to complex logic, prefer clear self-documenting code
- **Indentation**: 4 spaces, not tabs

## Project Structure
- Follow the standard Swift Package Manager structure with modules in Sources/
- Organize code into feature directories with Models, Views, and Managers subdirectories