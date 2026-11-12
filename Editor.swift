import AppKit
import SwiftUI

struct Key: Identifiable {
    let id: String
    let width: Double
    init(_ name: String, _ width: Double = 1) {
        id = name
        self.width = width
    }

    var label: String {
        switch id {
        case "RShift": "Shift"
        case "RCtrl": "Ctrl"
        case "RAlt": "Alt"
        case "Back": "Delete"
        case "Space": "Space"
        case "App": "Menu"
        case "+": "="
        case "<": ","
        case ">": "."
        case "?": "/"
        default: id
        }
    }
}

let rows: [[Key]] = [
    ["Esc", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "+"].map { Key($0) } + [Key("Back", 2)],
    [Key("Tab", 1.5)] + ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]"].map { Key($0) } + [Key("\\", 1.5)],
    [Key("Caps", 1.75)] + ["A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'"].map { Key($0) } + [Key("Enter", 2.25)],
    [Key("Shift", 2.25)] + ["Z", "X", "C", "V", "B", "N", "M", "<", ">", "?"].map { Key($0) } + [Key("RShift", 2.75)],
    [Key("Ctrl", 1.25), Key("Win", 1.25), Key("Alt", 1.25), Key("Space", 6.25),
     Key("RAlt", 1.25), Key("App", 1.25), Key("RCtrl", 1.25), Key("Fn", 1.25)]
]
let allKeys = rows.flatMap { $0 }
let black = "000000"

func rgbColor(_ hex: String) -> Color {
    let value = UInt32(hex, radix: 16) ?? 0
    return Color(.sRGB, red: Double(value >> 16) / 255,
                 green: Double((value >> 8) & 255) / 255,
                 blue: Double(value & 255) / 255)
}

func hexColor(_ color: Color) -> String {
    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return black }
    return String(format: "%02X%02X%02X", colorByte(rgb.redComponent), colorByte(rgb.greenComponent), colorByte(rgb.blueComponent))
}

func colorByte(_ component: CGFloat) -> Int {
    Int((min(max(component, 0), 1) * 255).rounded())
}

func scaledRGB(_ hex: String, brightness: Int) -> String {
    guard let value = UInt32(hex, radix: 16) else { return black }
    let percent = min(max(brightness, 0), 100)
    let channels = [16, 8, 0].map { shift in
        let channel = Int((value >> shift) & 255)
        return (channel * percent + 50) / 100
    }
    return String(format: "%02X%02X%02X", channels[0], channels[1], channels[2])
}

struct ProbeResult: Sendable {
    let success: Bool
    let message: String
    let output: String
}

func runProbe(_ executable: URL, _ arguments: [String]) -> ProbeResult {
    let process = Process()
    let output = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = output

    do {
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let transcript = String(decoding: data, as: UTF8.self)
        let lines = transcript.split(separator: "\n")
        let failure = lines.last { line in
            ["HID open failed", "HID write failed", "Expected one", "No matching", "Keyboard did not"]
                .contains { line.hasPrefix($0) }
        }
        return ProbeResult(success: process.terminationStatus == 0,
                           message: failure.map(String.init) ?? "Probe exited with status \(process.terminationStatus).",
                           output: transcript)
    } catch {
        return ProbeResult(success: false, message: error.localizedDescription, output: "")
    }
}

struct KicktrollPreset: Decodable, Identifiable {
    let id: String
    let name: String
    let category: String
    let colors: [String: String]

    static let bundled: [Self] = {
        guard let url = Bundle.main.url(forResource: "Kicktroll-Presets", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let presets = try? JSONDecoder().decode([Self].self, from: data) else { return [] }
        return presets
    }()
}

@MainActor
final class EditorState: ObservableObject {
    @Published var effect = -1
    @Published var effectSpeed = 2
    @Published var colors: [String: String] = [:]
    @Published var selected: Set<String> = []
    @Published var brush = Color(red: 0, green: 0.38, blue: 1)
    @Published var presetName = ""
    @Published var loadedPreset = ""
    @Published var isSaving = false
    @Published var isApplying = false
    @Published var failed = false
    @Published var status = "Load a preset or select keys to start painting."
}

struct Editor: View {
    @ObservedObject var model: EditorState
    @AppStorage("presets") private var presetData = Data()
    @AppStorage("brightness") private var brightness = 100.0

    private var presets: [String: [String: String]] {
        (try? JSONDecoder().decode([String: [String: String]].self, from: presetData)) ?? [:]
    }

    private var kicktrollCategories: [String: [KicktrollPreset]] {
        Dictionary(grouping: KicktrollPreset.bundled, by: \.category)
    }

    private var arguments: [String] {
        if model.effect >= 0 {
            let mode = brightness == 0 ? 0 : model.effect
            let level = Int((brightness * 4 / 100).rounded())
            return ["effect", String(mode), String(level), String(model.effectSpeed)]
        }
        return ["set"] + allKeys.flatMap { [$0.id, displayedColor(for: $0)] }
    }

    private func displayedColor(for key: Key) -> String {
        scaledRGB(model.colors[key.id] ?? black, brightness: Int(brightness))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MK1300 RGB").font(.largeTitle.bold())
                    Text("Ant Esports MK1300 V2 · 36AE:FE12").foregroundStyle(.secondary)
                }
                Spacer()
                Menu("Presets") {
                    Menu("Kicktroll") {
                        ForEach(kicktrollCategories.keys.sorted(), id: \.self) { category in
                            Menu(category) {
                                ForEach(kicktrollCategories[category, default: []]) { preset in
                                    Button(preset.name) {
                                        model.effect = -1
                                        model.colors = preset.colors
                                        model.loadedPreset = ""
                                        model.status = "Loaded \(preset.name). Click Apply to send it to the keyboard."
                                        model.failed = false
                                    }
                                }
                            }
                        }
                    }
                    Divider()
                    ForEach(presets.keys.sorted(), id: \.self) { name in
                        Button(name) {
                            model.effect = -1
                            model.colors = presets[name] ?? [:]
                            model.loadedPreset = name
                            model.status = "Loaded \(name). Click Apply to send it to the keyboard."
                            model.failed = false
                        }
                    }
                    if presets.isEmpty { Text("No saved presets") }
                }
                Button("Save Preset…") {
                    model.presetName = model.loadedPreset
                    model.isSaving = true
                }
            }
            .disabled(model.isApplying)

            HStack(spacing: 16) {
                Picker("Lighting", selection: $model.effect) {
                    Text("Per-Key Layout").tag(-1)
                    Text("Breathing").tag(2)
                    Text("Swing").tag(3)
                    Text("Spin").tag(4)
                    Text("Stream").tag(5)
                    Text("Bloom").tag(6)
                    Text("Wave").tag(7)
                    Text("Cross").tag(8)
                    Text("Rain").tag(9)
                    Text("Meteor").tag(10)
                    Text("Reactive Spread").tag(11)
                    Text("Reverse Reactive Spread").tag(12)
                    Text("Reactive Key").tag(13)
                    Text("Sudoku").tag(14)
                    Text("Tide").tag(15)
                }
                .frame(width: 285)
                if model.effect >= 0 {
                    Picker("Speed", selection: $model.effectSpeed) {
                        ForEach(0...3, id: \.self) { Text(String($0 + 1)).tag($0) }
                    }
                    .frame(width: 105)
                }
                Spacer()
            }
            .disabled(model.isApplying)

            VStack(spacing: 6) {
                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: 6) {
                        ForEach(rows[index]) { key in keyButton(key) }
                    }
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .disabled(model.isApplying || model.effect >= 0)

            HStack(spacing: 10) {
                ColorPicker("Color", selection: $model.brush, supportsOpacity: false)
                Button("Paint") { paint(hexColor(model.brush)) }.disabled(model.selected.isEmpty)
                Button("Turn Off") { paint(black) }.disabled(model.selected.isEmpty)
                Divider().frame(height: 22)
                Button("Select All") { model.selected = Set(allKeys.map(\.id)) }
                Button("Deselect") { model.selected.removeAll() }.disabled(model.selected.isEmpty)
                Spacer()
                Text("\(model.selected.count) selected").foregroundStyle(.secondary)
            }
            .disabled(model.isApplying || model.effect >= 0)

            HStack(spacing: 10) {
                Slider(value: $brightness, in: 0...100, step: 1) {
                    Text("Brightness")
                }
                .frame(width: 320)
                Text("\(Int(brightness))%")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
                    .accessibilityHidden(true)
                Spacer()
            }
            .disabled(model.isApplying)
            .onChange(of: brightness) { _ in
                model.failed = false
                model.status = "Brightness changed. Click Apply to send it to the keyboard."
            }

            Divider()
            HStack {
                if model.isApplying { ProgressView().controlSize(.small) }
                Text(model.status)
                    .font(.callout)
                    .foregroundStyle(model.failed ? Color.red : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if model.failed {
                    Button("Copy Terminal Command", action: copyCommand)
                }
                Button("Apply to Keyboard", action: apply).buttonStyle(.borderedProminent)
                    .disabled(model.isApplying)
            }
        }
        .padding(24)
        .frame(width: 856)
        .frame(minHeight: 455)
        .alert("Save Preset", isPresented: $model.isSaving) {
            TextField("Preset name", text: $model.presetName)
            Button("Cancel", role: .cancel) {}
            Button("Save", action: savePreset)
        } message: {
            Text("Saving under an existing name replaces that preset.")
        }
    }

    private func keyButton(_ key: Key) -> some View {
        let hex = displayedColor(for: key)
        let chosen = model.selected.contains(key.id)
        return Button {
            if chosen { model.selected.remove(key.id) }
            else { model.selected.insert(key.id) }
        } label: {
            VStack(spacing: 5) {
                Text(key.label).font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Capsule()
                    .fill(hex == black ? Color.secondary.opacity(0.25) : rgbColor(hex))
                    .frame(width: 16, height: 4)
            }
            .foregroundStyle(.primary)
            .frame(width: 52 * key.width - 6, height: 49)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7).fill(rgbColor(hex).opacity(hex == black ? 0 : 0.24))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(chosen ? Color.accentColor : Color.secondary.opacity(0.22),
                                  lineWidth: chosen ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(key.label)
        .accessibilityValue("\(hex == black ? "Off" : "#\(hex)")\(chosen ? ", selected" : "")")
        .help(hex == black ? "\(key.label) · Off" : "\(key.label) · #\(hex)")
    }

    private func paint(_ hex: String) {
        for key in model.selected { model.colors[key] = hex }
        model.failed = false
        model.status = "Layout edited. Click Apply to send it to the keyboard."
    }

    private func savePreset() {
        let name = model.presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var updated = presets
        updated[name] = model.colors
        do {
            presetData = try JSONEncoder().encode(updated)
            model.loadedPreset = name
            model.status = "Saved \(name)."
            model.failed = false
        } catch {
            model.status = "Could not save \(name)."
        }
    }

    private func apply() {
        guard let probe = Bundle.main.url(forAuxiliaryExecutable: "rgb-probe") else {
            model.status = "The bundled keyboard probe is missing."
            return
        }
        let snapshot = arguments
        model.isApplying = true
        model.failed = false
        let applyingEffect = model.effect >= 0
        model.status = applyingEffect ? "Applying firmware effect…" : "Sending 61 colors…"
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                runProbe(probe, snapshot)
            }.value
            model.isApplying = false
            model.failed = !result.success
            let successMessage = applyingEffect ? "Keyboard confirmed the firmware mode." :
                "Keyboard acknowledged all 61 colors."
            model.status = result.success ? successMessage : result.message
        }
    }

    private func copyCommand() {
        guard let probe = Bundle.main.url(forAuxiliaryExecutable: "rgb-probe") else { return }
        let command = ([probe.path] + arguments).map { argument in
            "'" + argument.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
        }.joined(separator: " ")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        model.status = "Command copied. Paste it into Alacritty to apply this layout."
    }
}

@main
enum Launcher {
    static func main() {
        if CommandLine.arguments.dropFirst().first == "--list-layout" {
            allKeys.forEach { print($0.id) }
            return
        }
        if CommandLine.arguments.dropFirst().first == "--check-bundle" {
            guard let probe = Bundle.main.url(forAuxiliaryExecutable: "rgb-probe") else {
                fputs("The bundled keyboard probe is missing.\n", stderr)
                exit(1)
            }
            let result = runProbe(probe, ["keys"])
            let probeKeys = result.output.split(separator: "\n").map(String.init).sorted()
            let editorKeys = allKeys.map(\.id).sorted()
            guard result.success, probeKeys == editorKeys, Set(editorKeys).count == 61 else {
                fputs("The bundled probe or editor layout is invalid.\n", stderr)
                exit(1)
            }
            guard scaledRGB("FF8040", brightness: 0) == "000000",
                  scaledRGB("FF8040", brightness: 50) == "804020",
                  scaledRGB("FF8040", brightness: 100) == "FF8040",
                  scaledRGB("000000", brightness: 50) == "000000" else {
                fputs("Brightness scaling failed.\n", stderr)
                exit(1)
            }
            let catalog = KicktrollPreset.bundled
            guard catalog.count == 140, Set(catalog.map(\.id)).count == 140,
                  catalog.allSatisfy({ Set($0.colors.keys) == Set(editorKeys) }) else {
                fputs("The bundled Kicktroll preset catalog is invalid.\n", stderr)
                exit(1)
            }
            print("Bundled probe verified: 61 keys, brightness scaling, and 140 Kicktroll presets.")
            return
        }
        KeyboardEditorApp.main()
    }
}

struct KeyboardEditorApp: App {
    private let model = EditorState()

    var body: some Scene {
        Window("MK1300 RGB", id: "editor") { Editor(model: model) }
            .windowResizability(.contentSize)
    }
}
