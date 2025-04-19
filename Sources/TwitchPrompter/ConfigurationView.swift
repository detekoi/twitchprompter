import SwiftUI

struct ConfigurationView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Twitch")
                .font(.headline)
            HStack {
                Text("Channel:")
                    .frame(width: 120, alignment: .leading)
                TextField("Channel", text: $viewModel.twitchChannel)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(minWidth: 200)
            }
            HStack {
                Spacer()
                Button(viewModel.twitchConnected ? "Disconnect" : "Connect Twitch Account") {
                    viewModel.toggleTwitchConnection()
                }
                Text(viewModel.twitchConnected ? "Connected" : "Not Connected")
                    .foregroundColor(viewModel.twitchConnected ? .green : .red)
                Spacer()
            }

            Divider()

            Text("Google API")
                .font(.headline)
            HStack {
                Text("API Key:")
                    .frame(width: 120, alignment: .leading)
                SecureField("API Key", text: $viewModel.apiKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(minWidth: 200)
                    .onChange(of: viewModel.apiKey) { newValue in
                        viewModel.saveApiKey()
                    }
            }

            Divider()

            Text("Sources")
                .font(.headline)
            HStack {
                Text("Video:")
                    .frame(width: 120, alignment: .leading)
                Picker("", selection: $viewModel.selectedVideoSource) {
                    ForEach(viewModel.availableVideoSources, id: \.self) { source in
                        Text(source)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 200)
            }
            HStack {
                Text("Audio:")
                    .frame(width: 120, alignment: .leading)
                Picker("", selection: $viewModel.selectedAudioSource) {
                    ForEach(viewModel.availableAudioSources, id: \.self) { source in
                        Text(source)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 200)
            }

            Divider()

            HStack {
                Spacer()
                Button(viewModel.isStreaming ? "Stop Prompter" : "Start Prompter") {
                    if viewModel.isStreaming {
                        viewModel.stopStreaming()
                    } else {
                        viewModel.startStreaming()
                    }
                }
                .frame(minWidth: 140)
                Spacer()
            }
        }
        .padding(20)
        .onAppear {
            viewModel.loadApiKey()
            viewModel.discoverSources()
        }
        .frame(minWidth: 400, minHeight: 400)
    }
}