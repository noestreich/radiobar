import Foundation

/// Connects to an ICY (SHOUTcast/Icecast) stream as a secondary connection
/// purely to extract song title metadata. The main AVPlayer handles playback.
@MainActor
final class ICYMetadataFetcher: ObservableObject {
    @Published var currentTitle: String = ""

    private var fetchTask: Task<Void, Never>?

    func start(urlString: String) {
        fetchTask?.cancel()
        currentTitle = ""
        guard let url = URL(string: urlString) else { return }
        fetchTask = Task { [weak self] in
            await self?.fetch(from: url)
        }
    }

    func stop() {
        fetchTask?.cancel()
        fetchTask = nil
        currentTitle = ""
    }

    private func fetch(from url: URL) async {
        var request = URLRequest(url: url)
        request.setValue("1", forHTTPHeaderField: "Icy-MetaData")
        request.setValue("RadioBar/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let http = response as? HTTPURLResponse,
                  let metaIntStr = http.value(forHTTPHeaderField: "icy-metaint"),
                  let metaInt = Int(metaIntStr), metaInt > 0 else { return }

            // State machine: read audio bytes, then a length byte, then metadata
            var audioBytesLeft = metaInt
            var waitingForLength = false
            var metaBytesLeft = 0
            var metaBuffer: [UInt8] = []

            for try await byte in bytes {
                if Task.isCancelled { break }

                if waitingForLength {
                    let length = Int(byte) * 16
                    waitingForLength = false
                    if length > 0 {
                        metaBytesLeft = length
                        metaBuffer = []
                        metaBuffer.reserveCapacity(length)
                    } else {
                        audioBytesLeft = metaInt
                    }
                } else if metaBytesLeft > 0 {
                    metaBuffer.append(byte)
                    metaBytesLeft -= 1
                    if metaBytesLeft == 0 {
                        let raw = String(bytes: metaBuffer, encoding: .utf8)
                            ?? String(bytes: metaBuffer, encoding: .isoLatin1)
                            ?? ""
                        let title = parseTitle(from: raw)
                        if !title.isEmpty {
                            await MainActor.run { self.currentTitle = title }
                        }
                        audioBytesLeft = metaInt
                    }
                } else {
                    // Audio data – just count bytes
                    audioBytesLeft -= 1
                    if audioBytesLeft <= 0 {
                        waitingForLength = true
                    }
                }
            }
        } catch {
            // Stream doesn't support ICY or network error – silently ignore
        }
    }

    private func parseTitle(from metadata: String) -> String {
        // Format: StreamTitle='Artist - Title';StreamUrl='...';
        guard let start = metadata.range(of: "StreamTitle='"),
              let end   = metadata.range(of: "';", range: start.upperBound..<metadata.endIndex)
        else { return "" }
        return String(metadata[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespaces)
    }
}
