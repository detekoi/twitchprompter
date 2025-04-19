import SwiftUI

struct PromptView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var animate = false
    @State private var showHistory = false
    @State private var isExpanded: [String: Bool] = [:]
    @State private var viewMode: ViewMode = .cumulativeText
    
    enum ViewMode {
        case currentPrompt
        case cumulativeText
    }
    
    var body: some View {
        VStack(spacing: 15) {
            // View mode toggle
            Picker("Display Mode", selection: $viewMode) {
                Text("Latest").tag(ViewMode.currentPrompt)
                Text("All Responses").tag(ViewMode.cumulativeText)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            
            // Fixed height prompt container
            if viewMode == .currentPrompt {
                // Single latest prompt display
                VStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        ScrollViewReader { scrollView in
                            HStack(spacing: 0) {
                                Text(viewModel.currentPrompt)
                                    .id("promptText")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .lineLimit(3)
                                    .padding()
                                    .fixedSize(horizontal: true, vertical: false)
                                    .onChange(of: viewModel.currentPrompt) { _ in
                                        // Highlight and animate the text when it changes
                                        withAnimation(.easeIn(duration: 0.3)) {
                                            animate = true
                                        }
                                        
                                        // Reset scroll position to beginning
                                        scrollView.scrollTo("promptText", anchor: .leading)
                                        
                                        // After a brief delay, start auto-scrolling
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                            // Fade highlight
                                            withAnimation(.easeOut(duration: 0.3)) {
                                                animate = false
                                            }
                                            
                                            // Automatically scroll to end with smooth animation
                                            withAnimation(.linear(duration: Double(viewModel.currentPrompt.count) / 15)) {
                                                scrollView.scrollTo("promptText", anchor: .trailing)
                                            }
                                        }
                                    }
                            }
                            .frame(minHeight: 80)
                        }
                    }
                    .frame(height: 100)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
                    .opacity(animate ? 1 : 0.8)
                }
                .frame(height: 120)
            } else {
                // Cumulative text display
                ScrollViewReader { scrollView in
                    ScrollView {
                        Text(viewModel.cumulativeText)
                            .font(.body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("cumulativeText")
                            .onChange(of: viewModel.cumulativeText) { _ in
                                // Auto-scroll to bottom when content changes
                                withAnimation {
                                    scrollView.scrollTo("cumulativeText", anchor: .bottom)
                                }
                            }
                    }
                    .frame(height: 180)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(10)
                    .onAppear {
                        // Scroll to bottom when view appears
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation {
                                scrollView.scrollTo("cumulativeText", anchor: .bottom)
                            }
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