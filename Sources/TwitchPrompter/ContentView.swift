import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: AppViewModel
    var body: some View {
        if viewModel.isStreaming {
            PromptView()
        } else {
            ConfigurationView()
        }
    }
}