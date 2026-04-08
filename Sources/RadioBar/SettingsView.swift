import SwiftUI

// MARK: – Root

struct SettingsView: View {
    @EnvironmentObject var store:   StationStore
    @EnvironmentObject var player:  RadioPlayer
    @EnvironmentObject var hotkeys: HotkeyManager

    var body: some View {
        TabView {
            StationsTab()
                .tabItem { Label("Sender", systemImage: "radio") }
            HotkeysTab()
                .tabItem { Label("Tastenkürzel", systemImage: "keyboard") }
        }
        .frame(width: 540, height: 430)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .padding(.top, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: – Stations tab

private struct StationsTab: View {
    @EnvironmentObject var store: StationStore
    @State private var editing: Station? = nil
    @State private var isAdding    = false
    @State private var isSearching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: $store.autostartEnabled) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Beim Start automatisch spielen")
                    Text("Startet den ersten Sender in der Liste beim Öffnen der App")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            List {
                ForEach(store.stations) { station in
                    StationListRow(station: station) {
                        editing = station
                    } onDelete: {
                        store.deleteStation(station)
                    }
                }
                .onMove { store.move(from: $0, to: $1) }
            }
            .listStyle(.bordered)

            Divider()

            HStack {
                Text("\(store.stations.count) Sender")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Sender suchen…") { isSearching = true }
                    .buttonStyle(.bordered)
                Button("Sender hinzufügen") { isAdding = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .sheet(isPresented: $isSearching) {
            StationSearchView()
                .environmentObject(store)
        }
        .sheet(item: $editing) { station in
            EditStationSheet(
                title: "Sender bearbeiten",
                initialName: station.name,
                initialURL: station.url,
                initialColorHex: station.colorHex,
                initialHotkey: station.hotkeyConfig
            ) { name, url, colorHex, hotkey in
                var updated = station
                updated.name = name; updated.url = url
                updated.colorHex = colorHex; updated.hotkeyConfig = hotkey
                store.updateStation(updated)
                editing = nil
            } onCancel: { editing = nil }
        }
        .sheet(isPresented: $isAdding) {
            EditStationSheet(
                title: "Neuen Sender hinzufügen",
                initialName: "", initialURL: "", initialColorHex: "#007AFF"
            ) { name, url, colorHex, hotkey in
                store.addStation(Station(name: name, url: url,
                                        colorHex: colorHex, hotkeyConfig: hotkey))
                isAdding = false
            } onCancel: { isAdding = false }
        }
    }
}

// MARK: – Hotkeys tab

private struct HotkeysTab: View {
    @EnvironmentObject var hotkeys: HotkeyManager

    var body: some View {
        Form {
            Section {
                LabeledContent("Stumm schalten / Ton an") {
                    KeyRecorderButton(config: $hotkeys.muteConfig) { cfg in
                        hotkeys.updateMute(cfg)
                    }
                }
            } header: {
                Text("Wiedergabe")
            }

            Section {
                LabeledContent("Nächsten Sender") {
                    KeyRecorderButton(config: $hotkeys.cycleConfig) { cfg in
                        hotkeys.updateCycle(cfg)
                    }
                }
                LabeledContent("Vorherigen Sender") {
                    KeyRecorderButton(config: $hotkeys.cycleBackConfig) { cfg in
                        hotkeys.updateCycleBack(cfg)
                    }
                }
            } header: {
                Text("Sender wechseln")
            } footer: {
                Text("Läuft durch alle konfigurierten Sender und beginnt wieder von vorn.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Lauter") {
                    KeyRecorderButton(config: $hotkeys.volumeUpConfig) { cfg in
                        hotkeys.updateVolumeUp(cfg)
                    }
                }
                LabeledContent("Leiser") {
                    KeyRecorderButton(config: $hotkeys.volumeDownConfig) { cfg in
                        hotkeys.updateVolumeDown(cfg)
                    }
                }
            } header: {
                Text("Lautstärke")
            } footer: {
                Text("Ändert die Lautstärke in 5 %-Schritten. Funktioniert auch im Hintergrund.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: – Station list row

private struct StationListRow: View {
    let station:  Station
    let onEdit:   () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(station.color)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 1) {
                Text(station.name).font(.body)
                Text(station.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if hovered {
                Button("Bearbeiten") { onEdit() }
                    .buttonStyle(.borderless)
                    .font(.caption)

                Button { onDelete() } label: {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}

// MARK: – Add / Edit sheet

struct EditStationSheet: View {
    let title: String
    var onSave:   (String, String, String, HotkeyConfig?) -> Void
    var onCancel: () -> Void

    @State private var name:         String
    @State private var url:          String
    @State private var colorHex:     String
    @State private var hotkeyConfig: HotkeyConfig
    @State private var urlError:     String? = nil

    init(title: String, initialName: String, initialURL: String,
         initialColorHex: String, initialHotkey: HotkeyConfig? = nil,
         onSave: @escaping (String, String, String, HotkeyConfig?) -> Void,
         onCancel: @escaping () -> Void) {
        self.title = title; self.onSave = onSave; self.onCancel = onCancel
        _name         = State(initialValue: initialName)
        _url          = State(initialValue: initialURL)
        _colorHex     = State(initialValue: initialColorHex)
        _hotkeyConfig = State(initialValue: initialHotkey ?? .disabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.headline).padding(.bottom, 16)

            Form {
                LabeledContent("Name") {
                    TextField("z.B. Deutschlandfunk", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Stream-URL") {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("https://…", text: $url)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: url) { urlError = nil }
                        if let err = urlError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
                        Text("Direkte URL zum Audiostream (MP3, AAC, HLS …)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Akzentfarbe") {
                    HStack(spacing: 8) {
                        NSColorPickerView(colorHex: $colorHex)
                            .frame(width: 64, height: 28)
                        Circle()
                            .fill(Color(hex: colorHex) ?? .blue)
                            .frame(width: 16, height: 16)
                        Text(colorHex.uppercased())
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Globales Kürzel") {
                    KeyRecorderButton(config: $hotkeyConfig) { _ in }
                }
            }
            .padding(.bottom, 20)

            HStack {
                Spacer()
                Button("Abbrechen") { onCancel() }.keyboardShortcut(.cancelAction)
                Button(title.hasPrefix("Neu") ? "Hinzufügen" : "Speichern") {
                    guard validate() else { return }
                    onSave(name.trimmingCharacters(in: .whitespaces),
                           url.trimmingCharacters(in: .whitespaces),
                           colorHex,
                           hotkeyConfig.isEnabled ? hotkeyConfig : nil)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty ||
                          url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func validate() -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard let u = URL(string: trimmed), u.scheme == "http" || u.scheme == "https" else {
            urlError = "Bitte eine gültige http(s)-URL eingeben."
            return false
        }
        return true
    }
}
