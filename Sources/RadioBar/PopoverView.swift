import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var store:  StationStore
    @EnvironmentObject var player: RadioPlayer

    var body: some View {
        VStack(spacing: 0) {
            stationList
            metadataRow
            Divider().padding(.horizontal, 12)
            volumeRow
            Divider().padding(.horizontal, 12)
            bottomBar
        }
        .frame(width: 270)
        .background(.regularMaterial)
        // Sync current track title → Now Playing info center
        .onChange(of: player.currentMetadata) { _, title in
            player.refreshNowPlayingTitle(title, station: store.currentStation?.name ?? "")
        }
    }

    // MARK: – Station list

    private var stationList: some View {
        VStack(spacing: 5) {
            ForEach(Array(store.stations.enumerated()), id: \.element.id) { index, station in
                StationRow(
                    station:  station,
                    isActive: store.currentStationId == station.id,
                    shortcut: index < 9 ? "\(index + 1)" : nil
                ) {
                    toggleStation(station)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    // MARK: – Metadata / current track

    @ViewBuilder
    private var metadataRow: some View {
        let title = player.currentMetadata
        if !title.isEmpty {
            Divider().padding(.horizontal, 12)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
        }
    }

    // MARK: – Volume

    private var volumeRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Slider(
                value: Binding(
                    get: { Double(player.volume) },
                    set: { player.setVolume(Float($0)) }
                ),
                in: 0...1
            )
            .tint(accentColor)

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 18)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: – Bottom bar

    private var bottomBar: some View {
        HStack {
            Button {
                player.toggleMute()
            } label: {
                Text(player.isMuted ? "Ton an" : "Stumm")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(player.isMuted ? accentColor : .secondary)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: – Helpers

    private var accentColor: Color {
        store.currentStation?.color ?? .accentColor
    }

    private func toggleStation(_ station: Station) {
        if store.currentStationId == station.id && player.isPlaying {
            player.stop()
            store.currentStationId = nil
        } else {
            store.currentStationId = station.id
            player.play(station: station)
        }
    }

}

// MARK: – Station row button

private struct StationRow: View {
    let station:  Station
    let isActive: Bool
    let shortcut: String?
    let action:   () -> Void

    @State private var hovered = false

    var body: some View {
        let btn = Button(action: action) {
            HStack(spacing: 8) {
                if let key = shortcut {
                    Text(key)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(isActive ? .white.opacity(0.7) : .secondary)
                        .frame(width: 12)
                }
                Text(station.name)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? .white : .primary)
                Spacer()
                if isActive {
                    Image(systemName: "waveform")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.8))
                        .symbolEffect(.variableColor.iterative.dimInactiveLayers, isActive: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive
                          ? station.color
                          : (hovered ? Color.primary.opacity(0.07) : Color.clear))
            }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }

        if let key = shortcut, let ch = key.first {
            btn.keyboardShortcut(KeyEquivalent(ch), modifiers: [])
        } else {
            btn
        }
    }
}
