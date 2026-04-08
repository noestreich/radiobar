import Foundation
import Combine

@MainActor
final class StationStore: ObservableObject {
    @Published var stations: [Station] = []
    @Published var currentStationId: UUID?
    @Published var autostartEnabled: Bool {
        didSet { UserDefaults.standard.set(autostartEnabled, forKey: "radiobar_autostart") }
    }

    private let key = "radiobar_stations"

    init() {
        autostartEnabled = UserDefaults.standard.bool(forKey: "radiobar_autostart")
        load()
        if stations.isEmpty {
            stations = [
                Station(name: "Deutschlandfunk",
                        url: "https://st01.sslstream.dlf.de/dlf/01/128/mp3/stream.mp3",
                        colorHex: "#007AFF"),
                Station(name: "DLF Kultur",
                        url: "https://st02.sslstream.dlf.de/dlf/02/128/mp3/stream.mp3",
                        colorHex: "#34C759"),
                Station(name: "DLF Nova",
                        url: "https://st03.sslstream.dlf.de/dlf/03/128/mp3/stream.mp3",
                        colorHex: "#FF9500"),
            ]
            save()
        }
    }

    func addStation(_ station: Station) {
        stations.append(station)
        save()
    }

    func updateStation(_ station: Station) {
        guard let idx = stations.firstIndex(where: { $0.id == station.id }) else { return }
        stations[idx] = station
        save()
    }

    func deleteStation(_ station: Station) {
        stations.removeAll { $0.id == station.id }
        if currentStationId == station.id { currentStationId = nil }
        save()
    }

    func move(from: IndexSet, to: Int) {
        stations.move(fromOffsets: from, toOffset: to)
        save()
    }

    var currentStation: Station? {
        stations.first { $0.id == currentStationId }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Station].self, from: data) else { return }
        stations = decoded
    }

    func save() {
        guard let encoded = try? JSONEncoder().encode(stations) else { return }
        UserDefaults.standard.set(encoded, forKey: key)
    }
}
