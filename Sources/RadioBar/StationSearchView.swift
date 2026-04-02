import SwiftUI

struct StationSearchView: View {
    @EnvironmentObject var store: StationStore
    @StateObject private var service = StreamURLService()
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyDraft = ""
    @State private var addingID: String? = nil
    @State private var addedIDs: Set<String> = []
    @State private var addError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if service.apiKey.isEmpty {
                apiKeyView
            } else {
                searchView
            }
        }
        .frame(width: 500, height: 520)
    }

    // MARK: – Header

    private var header: some View {
        HStack {
            Text("Sender suchen")
                .font(.headline)
            Spacer()
            Button("Fertig") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: – API key entry

    private var apiKeyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "key.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("StreamURL API-Key")
                .font(.title3.weight(.semibold))

            Text("Gib deinen persönlichen API-Key ein.\nEr wird einmalig sicher im macOS-Schlüsselbund gespeichert.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SecureField("API-Key eingeben…", text: $apiKeyDraft)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)

            Button("Speichern") {
                service.saveAPIKey(apiKeyDraft)
            }
            .buttonStyle(.borderedProminent)
            .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    // MARK: – Search

    private var searchView: some View {
        VStack(spacing: 0) {
            // Search bar + key indicator
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Sendername, Genre oder Land…", text: $service.query)
                        .textFieldStyle(.plain)
                    if service.isSearching {
                        ProgressView().controlSize(.small)
                    } else if !service.query.isEmpty {
                        Button {
                            service.query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(9)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1))
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Error banner
            if let err = service.errorMessage ?? addError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(err)
                        .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }

            Divider()

            // Results / placeholder
            resultList

            Divider()

            // Footer
            HStack {
                Label(
                    "API-Key: " + String(service.apiKey.prefix(6)) + "••••",
                    systemImage: "key"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Key ändern") {
                    service.clearAPIKey()
                    apiKeyDraft = ""
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var resultList: some View {
        if service.results.isEmpty && !service.isSearching {
            VStack {
                Spacer()
                Text(service.query.count < 2
                     ? "Mindestens 2 Zeichen eingeben"
                     : "Keine Ergebnisse für \"\(service.query)\"")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List(service.results) { station in
                SearchResultRow(
                    station:  station,
                    isAdding: addingID == station.id,
                    isAdded:  addedIDs.contains(station.id)
                ) {
                    Task { await addStation(station) }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: – Add station

    private func addStation(_ station: SURLStation) async {
        guard addingID == nil else { return }
        addingID = station.id
        addError = nil
        do {
            let streamURL = try await service.bestStream(for: station.id)
            store.addStation(Station(name: station.name, url: streamURL, colorHex: "#007AFF"))
            addedIDs.insert(station.id)
        } catch {
            addError = error.localizedDescription
        }
        addingID = nil
    }
}

// MARK: – Result row

private struct SearchResultRow: View {
    let station:  SURLStation
    let isAdding: Bool
    let isAdded:  Bool
    let onAdd:    () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Logo
            AsyncImage(url: station.absoluteLogoURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.secondary.opacity(0.12))
                    Image(systemName: "radio")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 7))

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(station.name)
                        .font(.body)
                        .lineLimit(1)
                    if station.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.blue)
                    }
                }

                HStack(spacing: 4) {
                    if !station.flagEmoji.isEmpty {
                        Text(station.flagEmoji)
                    }
                    if let country = station.country {
                        Text(country)
                    }
                    if !station.genres.isEmpty {
                        Text("·")
                        Text(station.genres.prefix(2).joined(separator: ", "))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            // Action
            actionButton
                .frame(width: 28)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var actionButton: some View {
        if isAdded {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
        } else if isAdding {
            ProgressView().controlSize(.small)
                .frame(width: 22, height: 22)
        } else {
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Sender zur Liste hinzufügen")
        }
    }
}
