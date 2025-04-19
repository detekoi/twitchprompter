import SwiftUI

struct PromptView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var animate = false // Keep for potential future use or remove if unused
    @State private var showHistory = false
    @State private var isExpanded: [String: Bool] = [:]
    // Removed viewMode state and enum

    var body: some View {
        VStack(spacing: 15) {
            // Removed Picker

            // Display cumulative text with larger font and auto-scroll
            ScrollViewReader { scrollView in
                ScrollView {
                    // Setup text view for continuous scrolling text
                    Text(viewModel.cumulativeText)
                        .font(.title3) // Use larger font
                        .fontWeight(.bold) // Use bold weight
                        .lineSpacing(4) // Keep line spacing
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("cumulativeText")
                        .onChange(of: viewModel.cumulativeText) { _ in
                            // Auto-scroll to bottom when content changes
                            withAnimation {
                                scrollView.scrollTo("cumulativeText", anchor: .bottomTrailing)
                            }
                        }
                }
                .frame(height: 180) // Keep fixed height or adjust as needed
                .background(Color.blue.opacity(0.05)) // Keep background style
                .cornerRadius(10) // Keep corner radius
                .onAppear {
                    // Scroll to bottom when view appears
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation {
                            scrollView.scrollTo("cumulativeText", anchor: .bottomTrailing)
                        }
                    }
                }
            }

            // Toggle for showing message history
            Button(action: {
                withAnimation {
                    showHistory.toggle()
                }
            }) {
                HStack {
                    Text(showHistory ? "Hide Message History" : "Show Message History")
                    if !viewModel.messageHistory.isEmpty {
                        Text("(\(viewModel.messageHistory.count))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, -4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(8)
            }
            
            // Message history with fixed height
            if showHistory {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.messageHistory, id: \.self) { message in
                            // Split into timestamp and content
                            let components = message.components(separatedBy: "] ")
                            let messageId = message
                            let hasTimestamp = components.count > 1
                            let timestamp = hasTimestamp ? components[0] + "]" : ""
                            let content = hasTimestamp ? components[1...].joined(separator: "] ") : message
                            
                            VStack(alignment: .leading) {
                                HStack {
                                    if hasTimestamp {
                                        Text(timestamp)
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                    }
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        withAnimation {
                                            if isExpanded[messageId] == nil {
                                                isExpanded[messageId] = true
                                            } else {
                                                isExpanded[messageId]?.toggle()
                                            }
                                        }
                                    }) {
                                        Image(systemName: (isExpanded[messageId] ?? false) ? "chevron.up" : "chevron.down")
                                            .font(.caption)
                                    }
                                }
                                
                                if isExpanded[messageId] ?? true {
                                    Text(content)
                                        .fixedSize(horizontal: false, vertical: true)
                                } else {
                                    Text(content)
                                        .lineLimit(2)
                                        .truncationMode(.tail)
                                }
                            }
                            .font(.body)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(5)
                            .onAppear {
                                // Expand the most recent message by default
                                if viewModel.messageHistory.first == message {
                                    isExpanded[messageId] = true
                                }
                            }
                        }
                    }
                    .padding()
                }
                .frame(height: 250)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            Spacer(minLength: 0)
        }
        .frame(maxHeight: 500)
        .padding()
    }
}
