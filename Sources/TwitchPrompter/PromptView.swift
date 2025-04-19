import SwiftUI

struct PromptView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var animate = false

    var body: some View {
        Text(viewModel.currentPrompt)
            .padding()
            .font(.title3)
            .multilineTextAlignment(.center)
            .opacity(animate ? 1 : 0.5)
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
    }
}