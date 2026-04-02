import Foundation
import Combine

// MARK: – API response models (snake_case decoded via .convertFromSnakeCase)

struct SURLStation: Codable, Identifiable, Sendable {
    let id:          String
    let name:        String
    let logoUrl:     String?
    let country:     String?
    let countryCode: String?
    let genres:      [String]
    let isVerified:  Bool

    /// Full logo URL (base + relative path from API).
    var absoluteLogoURL: URL? {
        guard let path = logoUrl, !path.isEmpty else { return nil }
        return URL(string: "https://api.streamurl.link/v1\(path)")
    }

    /// Country flag emoji from ISO 3166-1 alpha-2 code.
    var flagEmoji: String {
        guard let code = countryCode, code.count == 2 else { return "" }
        return code.uppercased().unicodeScalars
            .compactMap { Unicode.Scalar(127397 + $0.value) }
            .map { String($0) }
            .joined()
    }
}

struct SURLStream: Codable, Sendable {
    let url:         String
    let isPrimary:   Bool
    let bitrateKbps: Int?
}

private struct SearchEnvelope: Codable {
    let success: Bool
    let data:    [SURLStation]
}

private struct StreamsEnvelope: Codable {
    let success: Bool
    let data:    [SURLStream]
}

// MARK: – Errors

enum StreamURLError: LocalizedError {
    case noAPIKey, noStreams, rateLimited, http(Int)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:    return "Kein API-Key konfiguriert."
        case .noStreams:   return "Keine Stream-URL für diesen Sender verfügbar."
        case .rateLimited: return "Zu viele Anfragen – kurz warten und erneut versuchen."
        case .http(let c): return "Serverfehler \(c)."
        }
    }
}

// MARK: – Service

@MainActor
final class StreamURLService: ObservableObject {

    // MARK: Published

    @Published var apiKey     = ""
    @Published var query      = ""
    @Published var results:   [SURLStation] = []
    @Published var isSearching = false
    @Published var errorMessage: String?

    // MARK: Private

    private let base = "https://api.streamurl.link/v1"
    private var cancellables = Set<AnyCancellable>()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: Init

    init() {
        apiKey = KeychainHelper.loadAPIKey() ?? ""
        installDebounce()
    }

    // MARK: – API key

    func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        KeychainHelper.saveAPIKey(trimmed)
        apiKey = trimmed
    }

    func clearAPIKey() {
        KeychainHelper.deleteAPIKey()
        apiKey = ""
        results = []
        query   = ""
    }

    // MARK: – Debounced search

    private func installDebounce() {
        $query
            .debounce(for: .milliseconds(350), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] term in
                guard let self else { return }
                let t = term.trimmingCharacters(in: .whitespaces)
                if t.count < 2 {
                    self.results = []
                    self.errorMessage = nil
                } else {
                    Task { await self.runSearch(t) }
                }
            }
            .store(in: &cancellables)
    }

    private func runSearch(_ term: String) async {
        guard !apiKey.isEmpty else { errorMessage = "Kein API-Key gespeichert."; return }
        var comps = URLComponents(string: "\(base)/search")!
        comps.queryItems = [URLQueryItem(name: "q", value: term)]
        guard let url = comps.url else { return }

        isSearching  = true
        errorMessage = nil
        do {
            let envelope: SearchEnvelope = try await fetch(url: url)
            results = envelope.data
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
        isSearching = false
    }

    // MARK: – Best stream

    func bestStream(for stationID: String) async throws -> String {
        guard !apiKey.isEmpty else { throw StreamURLError.noAPIKey }
        let url = URL(string: "\(base)/stations/\(stationID)/streams")!
        let envelope: StreamsEnvelope = try await fetch(url: url)
        guard !envelope.data.isEmpty else { throw StreamURLError.noStreams }
        let streams = envelope.data
        if let primary = streams.first(where: { $0.isPrimary }) { return primary.url }
        return streams.max(by: { ($0.bitrateKbps ?? 0) < ($1.bitrateKbps ?? 0) })?.url ?? streams[0].url
    }

    // MARK: – HTTP helper

    private func fetch<T: Decodable>(url: URL) async throws -> T {
        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        req.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200:  break
            case 429:  throw StreamURLError.rateLimited
            default:   throw StreamURLError.http(http.statusCode)
            }
        }
        return try decoder.decode(T.self, from: data)
    }
}
