import SwiftUI

struct ContentView: View {
    @StateObject private var vm = StreamViewModel()
    @AppStorage("host") private var host = ""
    @AppStorage("port") private var port = 8000
    @AppStorage("portIsListener") private var portIsListener = true
    @State private var password = ""            // intentionally not persisted
    @AppStorage("name") private var name = "My Station"
    @AppStorage("genre") private var genre = "Various"
    @AppStorage("url") private var url = ""
    @AppStorage("isPublic") private var isPublic = false
    @AppStorage("bitrate") private var bitrate = 128
    @AppStorage("sampleRate") private var sampleRate = 44100
    @AppStorage("stereo") private var stereo = true
    @State private var title = ""

    private var config: StreamConfig {
        .init(host: host.trimmingCharacters(in: .whitespaces), port: port, portIsListener: portIsListener,
              password: password, name: name, genre: genre, url: url, isPublic: isPublic,
              bitrate: bitrate, sampleRate: Double(sampleRate), stereo: stereo)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Host", text: $host)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("Port", value: $port, format: .number.grouping(.never)).keyboardType(.numberPad)
                    Toggle("Port is listener port (connect to port + 1)", isOn: $portIsListener)
                    SecureField("Source password", text: $password)
                }.disabled(vm.isBusy)

                Section("Station") {
                    TextField("Name", text: $name)
                    TextField("Genre", text: $genre)
                    TextField("URL", text: $url).textInputAutocapitalization(.never).keyboardType(.URL)
                    Toggle("List publicly", isOn: $isPublic)
                }.disabled(vm.isBusy)

                Section("Audio (MP3)") {
                    Picker("Bitrate", selection: $bitrate) {
                        ForEach([64, 96, 128, 192, 256, 320], id: \.self) { Text("\($0) kbps").tag($0) }
                    }
                    Picker("Sample rate", selection: $sampleRate) {
                        Text("44.1 kHz").tag(44100); Text("48 kHz").tag(48000)
                    }
                    Toggle("Stereo", isOn: $stereo)
                }.disabled(vm.isBusy)

                Section("Now playing") {
                    TextField("Artist - Title", text: $title)
                    Button("Update title") { vm.updateTitle(title, config: config) }
                        .disabled(vm.phase != .live || title.isEmpty)
                    if !vm.titleStatus.isEmpty { Text(vm.titleStatus).font(.footnote).foregroundStyle(.secondary) }
                }

                Section {
                    Button {
                        vm.isBusy ? vm.stop() : vm.start(config)
                    } label: {
                        Text(vm.isBusy ? "Stop" : "Go Live").font(.title2.bold()).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .tint(vm.isBusy ? .red : .green)

                    ProgressView(value: Double(vm.level))
                    LabeledContent("Status", value: statusText)
                    if vm.phase == .live {
                        LabeledContent("Time", value: clock(vm.elapsed))
                        LabeledContent("Sent", value: ByteCountFormatter.string(fromByteCount: Int64(vm.bytesSent), countStyle: .file))
                    }
                }
            }
            .navigationTitle("SHOUTcast Encoder")
        }
        .navigationViewStyle(.stack)
    }

    private var statusText: String {
        switch vm.phase {
        case .idle: return "Offline"
        case .connecting: return "Connecting…"
        case .live: return "On air"
        case .error(let m): return m
        }
    }

    private func clock(_ t: TimeInterval) -> String {
        let s = Int(t); return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }
}
