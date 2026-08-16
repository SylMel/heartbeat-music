import HeartbeatCore
import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var viewModel: NowPlayingViewModel

    private let accent = Color(red: 1.0, green: 0.27, blue: 0.42)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.06, blue: 0.14),
                    Color(red: 0.16, green: 0.07, blue: 0.14),
                    Color(red: 0.05, green: 0.08, blue: 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header
                    spotifyCard
                    sourceSelector
                    modeSelector
                    heartRateCard
                    trackCard
                    syncControl
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var spotifyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("MUSIC SERVICE", systemImage: "music.note.list")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("SPOTIFY")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.green)
            }

            HStack(spacing: 12) {
                Image(systemName: spotifyStatusIcon)
                    .font(.title2)
                    .foregroundStyle(spotifyStatusColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.spotifyConnectionState.message)
                        .font(.subheadline.weight(.semibold))
                    Text(spotifyDetailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button(viewModel.spotifyConnectionState.isConnected ? "Disconnect" : "Connect") {
                    if viewModel.spotifyConnectionState.isConnected {
                        viewModel.disconnectSpotify()
                    } else {
                        viewModel.connectSpotify()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.spotifyConnectionState.isConnected ? .secondary : .green)
                .accessibilityIdentifier("spotifyConnectButton")
            }

            Divider().overlay(.white.opacity(0.1))

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ACTIVE CATALOG")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(viewModel.activeCatalogName)
                        .font(.subheadline.weight(.semibold))
                    Text("\(viewModel.activeCatalogTrackCount) BPM-matched tracks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.activeCatalogName != "Demo catalog" {
                    Button("Use demo") {
                        viewModel.useDemoCatalog()
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            Text(viewModel.catalogMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.spotifyConnectionState.isConnected {
                DisclosureGroup("Import a Spotify playlist") {
                    VStack(alignment: .leading, spacing: 12) {
                        if viewModel.hasBPMAPIKey {
                            Label("BPM lookup ready", systemImage: "checkmark.shield.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        } else {
                            Text("Spotify supplies the songs; GetSongBPM supplies their tempos.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            SecureField(
                                viewModel.hasBPMAPIKey
                                    ? "Replace BPM API key (optional)"
                                    : "GetSongBPM API key",
                                text: $viewModel.bpmAPIKeyInput
                            )
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))

                            Button("Save") {
                                viewModel.saveBPMAPIKey()
                            }
                            .disabled(viewModel.bpmAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        Link(destination: URL(string: "https://getsongbpm.com/api")!) {
                            Label("Get a free API key · BPM data by GetSongBPM.com", systemImage: "arrow.up.right.square")
                                .font(.caption)
                        }

                        Button {
                            viewModel.loadSpotifyPlaylists()
                        } label: {
                            Label("Load my playlists", systemImage: "arrow.down.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isCatalogBusy)

                        if !viewModel.spotifyPlaylists.isEmpty {
                            Picker("Playlist", selection: $viewModel.selectedSpotifyPlaylistID) {
                                ForEach(viewModel.spotifyPlaylists) { playlist in
                                    if let saved = viewModel.importedCatalogs[playlist.id] {
                                        Text("✓ \(playlist.name) (\(saved.tracks.count) matched)")
                                            .tag(playlist.id)
                                    } else {
                                        Text("\(playlist.name) (\(playlist.itemCount))")
                                            .tag(playlist.id)
                                    }
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.green)

                            if let playlist = viewModel.spotifyPlaylists.first(where: {
                                $0.id == viewModel.selectedSpotifyPlaylistID
                            }), let spotifyURL = playlist.spotifyURL {
                                Link("Open selected playlist in Spotify", destination: spotifyURL)
                                    .font(.caption)
                            }

                            if let saved = viewModel.importedCatalogs[viewModel.selectedSpotifyPlaylistID] {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(
                                        "Previously matched: \(saved.tracks.count) tracks",
                                        systemImage: "checkmark.circle.fill"
                                    )
                                    .foregroundStyle(.green)
                                    .font(.caption.weight(.semibold))

                                    Text("Saved \(saved.importedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                    Button("Use saved BPM catalog") {
                                        viewModel.useSavedCatalogForSelectedPlaylist()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }

                            Button {
                                viewModel.importSelectedSpotifyPlaylist()
                            } label: {
                                Label("Import and find BPM", systemImage: "magnifyingglass")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(viewModel.isCatalogBusy || !viewModel.hasBPMAPIKey)
                        }

                        if let progress = viewModel.catalogProgress {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(.green)
                                Text(progress)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 12)
                }
                .font(.subheadline.weight(.semibold))
                .tint(.green)
            }
        }
        .padding(16)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20))
    }

    private var spotifyStatusIcon: String {
        switch viewModel.spotifyConnectionState {
        case .connected: "checkmark.circle.fill"
        case .authorizing, .connecting: "arrow.triangle.2.circlepath.circle.fill"
        case .spotifyNotInstalled, .failed: "exclamationmark.triangle.fill"
        case .disconnected: "music.note"
        }
    }

    private var spotifyStatusColor: Color {
        switch viewModel.spotifyConnectionState {
        case .connected: .green
        case .spotifyNotInstalled, .failed: .orange
        default: .secondary
        }
    }

    private var spotifyDetailText: String {
        if let spotifyNowPlaying = viewModel.spotifyNowPlaying {
            return spotifyNowPlaying
        }
        if viewModel.spotifyConnectionState.isConnected {
            return "Playback control and playlist access are ready"
        }
        return "Connects playback and asks permission to read playlists"
    }

    private var sourceSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("HEART RATE SOURCE", systemImage: "heart.text.clipboard")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("Heart rate source", selection: $viewModel.heartRateInput) {
                    ForEach(HeartRateInputKind.allCases) { source in
                        Label(source.title, systemImage: source.icon)
                            .tag(source)
                    }
                }
                .pickerStyle(.menu)
                .tint(accent)
                .accessibilityIdentifier("heartRateSourcePicker")
            }

            HStack(spacing: 10) {
                Image(systemName: sourceStatusIcon)
                    .foregroundStyle(sourceStatusColor)
                Text(viewModel.sourceStatus.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.heartRateInput == .myzone {
                    Button("Scan again") {
                        viewModel.retryHeartRateSource()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                }
            }
        }
        .padding(16)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20))
    }

    private var sourceStatusIcon: String {
        switch viewModel.sourceStatus {
        case .connected: "checkmark.circle.fill"
        case .scanning, .connecting, .ready: "antenna.radiowaves.left.and.right"
        case .unavailable, .failed: "exclamationmark.triangle.fill"
        case .idle: "circle.dashed"
        }
    }

    private var sourceStatusColor: Color {
        switch viewModel.sourceStatus {
        case .connected: .green
        case .unavailable, .failed: .orange
        default: accent
        }
    }

    private var modeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MODE")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            Picker("Mode", selection: $viewModel.mode) {
                Label("Workout", systemImage: "figure.run")
                    .tag(HeartbeatMode.workout)
                Label("Relax", systemImage: "leaf.fill")
                    .tag(HeartbeatMode.relax)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("modePicker")

            Label(modeDescription, systemImage: modeDescriptionIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20))
    }

    private var modeDescription: String {
        switch viewModel.mode {
        case .workout:
            "Matches your activity; waits 3:30 before moving down"
        case .relax:
            "Targets music 15 BPM below your heart rate"
        }
    }

    private var modeDescriptionIcon: String {
        switch viewModel.mode {
        case .workout: "arrow.up.arrow.down"
        case .relax: "arrow.down.heart.fill"
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("HEARTBEAT MUSIC")
                    .font(.caption.weight(.bold))
                    .tracking(2.4)
                    .foregroundStyle(accent)
                Text("Move to your rhythm")
                    .font(.title2.weight(.semibold))
            }
            Spacer()
            Image(systemName: "waveform.path.ecg")
                .font(.title2)
                .foregroundStyle(accent)
                .padding(12)
                .background(.white.opacity(0.08), in: Circle())
        }
    }

    private var heartRateCard: some View {
        VStack(spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                Label("HEART RATE", systemImage: "heart.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(heartRateStatusLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(viewModel.isSyncEnabled ? accent : .secondary)
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(viewModel.hasHeartRateReading ? "\(Int(viewModel.heartRate.rounded()))" : "––")
                    .font(.system(size: 76, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("BPM")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
                Spacer()
            }

            if viewModel.heartRateInput == .simulator {
                VStack(spacing: 10) {
                    Slider(
                        value: Binding(
                            get: { viewModel.heartRate },
                            set: { viewModel.setSimulatedHeartRate($0) }
                        ),
                        in: 60...180,
                        step: 1
                    )
                    .tint(accent)
                    .accessibilityIdentifier("heartRateSlider")

                    HStack {
                        Text("60")
                        Spacer()
                        Text("SIMULATED HEART RATE")
                        Spacer()
                        Text("180")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            } else {
                Label(inputHelpText, systemImage: viewModel.heartRateInput.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(22)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var heartRateStatusLabel: String {
        guard viewModel.isSyncEnabled else { return "SYNC PAUSED" }
        switch viewModel.heartRateInput {
        case .simulator:
            return "LIVE SIMULATION"
        case .myzone:
            return viewModel.hasHeartRateReading ? "MYZONE LIVE" : "WAITING FOR MYZONE"
        case .appleWatch:
            return viewModel.hasHeartRateReading ? "APPLE WATCH LIVE" : "WATCH NOT CONNECTED"
        }
    }

    private var inputHelpText: String {
        switch viewModel.heartRateInput {
        case .simulator:
            "Drag the slider to simulate a heart-rate reading."
        case .myzone:
            "Wear and activate your Myzone monitor, then keep this app open while it connects."
        case .appleWatch:
            "A future watchOS companion will relay live HealthKit heart-rate samples here."
        }
    }

    private var trackCard: some View {
        VStack(spacing: 20) {
            HStack {
                Text("CURRENT MATCH")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Label(matchRuleLabel, systemImage: matchRuleIcon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(accent)
            }

            HStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [accent, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "music.note")
                        .font(.system(size: 34, weight: .semibold))
                }
                .frame(width: 88, height: 88)

                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.selectedTrack?.title ?? "Finding your rhythm…")
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                    Text(viewModel.selectedTrack?.artist ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let track = viewModel.selectedTrack {
                        Text("\(Int(track.bpm.rounded())) BPM TRACK")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(accent)
                            .padding(.top, 4)
                    }
                }
                Spacer()
            }

            Divider().overlay(.white.opacity(0.1))

            if let remaining = viewModel.workoutSlowdownRemaining {
                HStack(spacing: 10) {
                    Image(systemName: "hourglass")
                        .foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HOLDING WORKOUT ENERGY")
                            .font(.caption2.weight(.bold))
                        Text("Lower tempo available in \(formattedDuration(remaining))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            }

            HStack {
                metric(title: "TARGET", value: "\(Int(viewModel.targetBPM.rounded()))", unit: "BPM")
                Spacer()
                metric(title: "SMOOTHED HR", value: "\(Int(viewModel.smoothedHeartRate.rounded()))", unit: "BPM")
            }
        }
        .padding(22)
        .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var matchRuleLabel: String {
        switch viewModel.mode {
        case .workout: "DIRECT BPM"
        case .relax: "15 BPM LOWER"
        }
    }

    private var matchRuleIcon: String {
        switch viewModel.mode {
        case .workout: "scope"
        case .relax: "leaf.fill"
        }
    }

    private var syncControl: some View {
        HStack(spacing: 14) {
            Image(systemName: viewModel.isSyncEnabled ? "bolt.heart.fill" : "pause.circle.fill")
                .font(.title2)
                .foregroundStyle(viewModel.isSyncEnabled ? accent : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sync to heart rate")
                    .font(.headline)
                Text(syncDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Sync to heart rate", isOn: $viewModel.isSyncEnabled)
                .labelsHidden()
                .tint(accent)
                .accessibilityIdentifier("syncToggle")
        }
        .padding(.horizontal, 4)
    }

    private var syncDescription: String {
        switch viewModel.mode {
        case .workout: "Follow activity with delayed slowdowns"
        case .relax: "Keep the music below your pulse"
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(ceil(duration))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func metric(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2.weight(.bold).monospacedDigit())
                Text(unit)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct NowPlayingView_Previews: PreviewProvider {
    static var previews: some View {
        NowPlayingView(viewModel: NowPlayingViewModel())
    }
}
