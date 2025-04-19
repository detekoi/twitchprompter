import SwiftUI

struct PromptView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var animate = false
    @State private var showHistory = false

    var body: some View {
        VStack(spacing: 20) {
            // Current prompt with animation
            Text(viewModel.currentPrompt)
                .padding()
                .font(.title3)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
                .opacity(animate ? 1 : 0.7)
                .onChange(of: viewModel.currentPrompt) { _ in
                    withAnimation(.easeIn(duration: 0.3)) {
                        animate = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            animate = false
                        }
                    }
                }
            
            // Toggle for showing history
            Button(action: {
                withAnimation {
                    showHistory.toggle()
                }
            }) {
                Text(showHistory ? "Hide Message History" : "Show Message History")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(8)
            }
            
            // Message history
            if showHistory {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.messageHistory, id: \.self) { message in
                            Text(message)
                                .font(.body)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(5)
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 300)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            Spacer()
        }
        .padding()
    }
}