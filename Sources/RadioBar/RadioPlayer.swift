import AVFoundation
import MediaPlayer
import Combine

@MainActor
final class RadioPlayer: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var isMuted   = false
    @Published var volume: Float = 0.7
    /// Current song title – forwarded from ICYMetadataFetcher so SwiftUI sees it.
    @Published var currentMetadata: String = ""

    let metadata = ICYMetadataFetcher()

    private var player: AVPlayer?
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var statusObserver: NSKeyValueObservation?
    private var metadataCancellable: AnyCancellable?

    /// Lautstärken pro Sender-ID, persistent in UserDefaults.
    private var volumePerStation: [String: Float] {
        get { UserDefaults.standard.dictionary(forKey: "radiobar_volumes") as? [String: Float] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "radiobar_volumes") }
    }
    private var currentStationID: String?

    override init() {
        super.init()
        setupMediaKeys()
        // Forward ICY title changes into our own @Published so views update.
        metadataCancellable = metadata.$currentTitle
            .receive(on: DispatchQueue.main)
            .assign(to: \.currentMetadata, on: self)
    }

    // MARK: – Playback control

    func play(station: Station) {
        // Lautstärke des aktuellen Senders sichern bevor gewechselt wird
        if let id = currentStationID {
            var vols = volumePerStation
            vols[id] = volume
            volumePerStation = vols
        }

        stop()
        guard let url = URL(string: station.url) else { return }

        // Gespeicherte Lautstärke des neuen Senders laden (Fallback: aktuelle)
        let stationID = station.id.uuidString
        currentStationID = stationID
        if let saved = volumePerStation[stationID] {
            volume = saved
        }

        let item = AVPlayerItem(url: url)
        attachMetadataOutput(to: item)

        player = AVPlayer(playerItem: item)
        player?.volume = isMuted ? 0 : volume
        player?.play()
        isPlaying = true

        metadata.start(urlString: station.url)
        updateNowPlaying(station: station)
    }

    func stop() {
        player?.pause()
        player = nil
        statusObserver = nil
        metadataOutput = nil
        isPlaying = false
        currentMetadata = ""
        metadata.stop()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func toggleMute() {
        isMuted.toggle()
        player?.volume = isMuted ? 0 : volume
    }

    func setVolume(_ v: Float) {
        volume = v
        if !isMuted { player?.volume = v }
        // Direkt persistieren damit auch manuelle Slider-Änderungen gespeichert werden
        if let id = currentStationID {
            var vols = volumePerStation
            vols[id] = v
            volumePerStation = vols
        }
    }

    // MARK: – HLS / timed metadata (for streams that provide it via AVFoundation)

    private func attachMetadataOutput(to item: AVPlayerItem) {
        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        output.setDelegate(self, queue: .main)
        item.add(output)
        metadataOutput = output
    }

    // MARK: – Now Playing info

    private func updateNowPlaying(station: Station) {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle]              = station.name
        info[MPNowPlayingInfoPropertyIsLiveStream]  = true
        info[MPMediaItemPropertyPlaybackDuration]   = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func refreshNowPlayingTitle(_ title: String, station: String) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle]  = title.isEmpty ? station : title
        info[MPMediaItemPropertyArtist] = title.isEmpty ? "" : station
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: – Media keys

    private func setupMediaKeys() {
        let cc = MPRemoteCommandCenter.shared()

        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause(); return .success
        }
        cc.playCommand.addTarget { [weak self] _ in
            self?.togglePlayPause(); return .success
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause(); return .success
        }
    }
}

// MARK: – AVPlayerItemMetadataOutputPushDelegate

extension RadioPlayer: AVPlayerItemMetadataOutputPushDelegate {
    nonisolated func metadataOutput(
        _ output: AVPlayerItemMetadataOutput,
        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
        from track: AVPlayerItemTrack?
    ) {
        for group in groups {
            for item in group.items {
                if let value = item.stringValue, !value.isEmpty {
                    Task { @MainActor [weak self] in
                        self?.currentMetadata = value
                    }
                }
            }
        }
    }
}
