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

let studioAccent = Color(red: 0.76, green: 0.96, blue: 0.46)
let studioBackground = Color(red: 0.06, green: 0.07, blue: 0.09)
let studioPanel = Color(red: 0.095, green: 0.105, blue: 0.135)
let firmwareEffects: [(Int, String)] = [(2, "Breathing"), (3, "Swing"), (4, "Spin"), (5, "Stream"),
    (6, "Bloom"), (7, "Wave"), (8, "Cross"), (9, "Rain"), (10, "Meteor"),
    (11, "Reactive Spread"), (12, "Reverse Reactive Spread"), (13, "Reactive Key"), (14, "Sudoku"), (15, "Tide")]

struct LightingSnapshot: Codable {
    var colors: [String: String]
    var effect: Int
    var speed: Int
    var name: String
}

func probeArguments(colors: [String: String], effect: Int, brightness: Double, speed: Int) -> [String] {
    let percent = min(max(Int(brightness), 0), 100)
    if effect >= 0 {
        return ["effect", String(percent == 0 ? 0 : effect), String(Int((Double(percent) * 4 / 100).rounded())), String(speed)]
    }
    return ["set"] + allKeys.flatMap { [$0.id, scaledRGB(colors[$0.id] ?? black, brightness: percent)] }
}

@MainActor
final class EditorState: ObservableObject {
    @Published var query = ""
    @Published var category = "All presets"
    @Published var savedOnly = false
    @Published var effect = -1
    @Published var effectSpeed = 2
    @Published var colors: [String: String] = [:]
    @Published var selected: Set<String> = []
    @Published var brush = Color(red: 0, green: 0.85, blue: 1)
    @Published var presetName = ""
    @Published var loadedPreset = ""
    @Published var layoutName = "Custom layout"
    @Published var isSaving = false
    @Published var isApplying = false
    @Published var failed = false
    @Published var lightingOff = false
    @Published var status = "Choose a preset or select keys to start painting."
    @Published var presets: [String: [String: String]] = [:]
    @Published var brightness: Double = 100 {
        didSet { UserDefaults.standard.set(brightness, forKey: "brightness") }
    }

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "presets"),
           let saved = try? JSONDecoder().decode([String: [String: String]].self, from: data) { presets = saved }
        if defaults.object(forKey: "brightness") != nil { brightness = min(max(defaults.double(forKey: "brightness"), 0), 100) }
        if let data = defaults.data(forKey: "lastAppliedLayout"),
           let last = try? JSONDecoder().decode(LightingSnapshot.self, from: data),
           Set(last.colors.keys).isSubset(of: Set(allKeys.map(\.id))),
           last.colors.values.allSatisfy({ $0.count == 6 && UInt32($0, radix: 16) != nil }),
           last.effect == -1 || firmwareEffects.contains(where: { $0.0 == last.effect }), (0...3).contains(last.speed) {
            colors = last.colors; effect = last.effect; effectSpeed = last.speed; layoutName = last.name
            status = "Last applied layout restored in the editor. Apply to send it again."
        } else if let rs = presets["RS"] {
            colors = rs; layoutName = "RS"; loadedPreset = "RS"
            status = "RS is ready. Apply to send it to your keyboard."
        }
    }

    var arguments: [String] { probeArguments(colors: colors, effect: effect, brightness: brightness, speed: effectSpeed) }
    var effectName: String { firmwareEffects.first(where: { $0.0 == effect })?.1 ?? "Per-key layout" }
    func displayedColor(_ key: Key) -> String { scaledRGB(colors[key.id] ?? black, brightness: Int(brightness)) }
    func load(_ name: String, colors: [String: String], saved: Bool = false) {
        guard !isApplying else { return }
        effect = -1; self.colors = colors; loadedPreset = saved ? name : ""; layoutName = name
        selected.removeAll(); failed = false
        status = "Loaded \(name). Apply when you’re ready."
    }
    func paint(_ hex: String) {
        guard !isApplying, effect == -1 else { return }
        for key in selected { colors[key] = hex }
        layoutName = "Custom layout"; loadedPreset = ""; failed = false
        status = "Layout edited. Apply to update your keyboard."
    }
    func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, effect == -1 else { return }
        var updated = presets; updated[name] = colors
        do {
            let data = try JSONEncoder().encode(updated)
            UserDefaults.standard.set(data, forKey: "presets"); presets = updated
            loadedPreset = name; layoutName = name; failed = false; status = "Saved \(name)."
        } catch { failed = true; status = "Could not save this preset: \(error.localizedDescription)" }
    }
    func apply(turnOff: Bool = false) {
        guard !isApplying else { return }
        guard let probe = Bundle.main.url(forAuxiliaryExecutable: "rgb-probe") else {
            failed = true; status = "The bundled keyboard probe is missing."; return
        }
        let snapshot = LightingSnapshot(colors: colors, effect: effect, speed: effectSpeed, name: layoutName)
        let args = turnOff ? ["effect", "0", "0", "2"] : arguments
        isApplying = true; failed = false
        status = turnOff ? "Turning lighting off…" : effect >= 0 ? "Applying \(effectName)…" : "Sending all 61 colors…"
        Task {
            let result = await Task.detached(priority: .userInitiated) { runProbe(probe, args) }.value
            isApplying = false; failed = !result.success
            if result.success {
                lightingOff = turnOff || brightness == 0
                status = turnOff ? "Keyboard lighting is off. Your layout is preserved." :
                    snapshot.effect >= 0 ? "Keyboard confirmed \(effectName), brightness, and speed." : "Keyboard confirmed all 61 colors."
                if !turnOff, let data = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(data, forKey: "lastAppliedLayout") }
            } else { status = result.message }
        }
    }
    func copyCommand() {
        guard let probe = Bundle.main.url(forAuxiliaryExecutable: "rgb-probe") else { return }
        let command = ([probe.path] + arguments).map { "'" + $0.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }.joined(separator: " ")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(command, forType: .string)
        status = "Command copied. Paste it into Terminal to apply this layout."
    }
}

struct StudioCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).background(studioPanel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.07), lineWidth: 1))
    }
}

struct SectionEyebrow: View {
    let title: String
    var body: some View { Text(title).font(.system(size: 9, weight: .bold)).tracking(1.8).foregroundStyle(studioAccent) }
}

struct BrightnessControl: View {
    @ObservedObject var model: EditorState
    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Label("Brightness", systemImage: "sun.max").font(.system(size: 12))
                Spacer()
                Text("\(Int(model.brightness))%").font(.system(size: 12, design: .monospaced)).foregroundStyle(studioAccent)
            }
            Slider(value: $model.brightness, in: 0...100, step: 1).labelsHidden().accessibilityLabel("Brightness")
                .onChange(of: model.brightness) { _ in
                    model.failed = false; model.status = "Brightness changed. Apply to update your keyboard."
                }
        }.disabled(model.isApplying)
    }
}

struct Editor: View {
    @ObservedObject var model: EditorState
    private let swatches = ["00D8FF", "C4F774", "FF2080", "A781FF", "FF9B53", "FFFFFF", "FF4545", "000000"]
    private var filteredPresets: [KicktrollPreset] {
        KicktrollPreset.bundled.filter { (model.category == "All presets" || $0.category == model.category) &&
            (model.query.isEmpty || $0.name.localizedCaseInsensitiveContains(model.query)) }
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(.white.opacity(0.05))
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        keyboardCard
                        HStack(alignment: .top, spacing: 16) { paintCard; lightingCard }
                    }.padding(24)
                }
                Divider().padding(.horizontal, 24)
                statusBar.padding(20)
            }.frame(width: 820)
        }
        .background(studioBackground)
        .preferredColorScheme(.dark)
        .tint(studioAccent)
        .frame(height: 718)
        .alert("Save Preset", isPresented: $model.isSaving) {
            TextField("Preset name", text: $model.presetName)
            Button("Cancel", role: .cancel) {}
            Button("Save", action: model.savePreset)
        } message: { Text("Saves your per-key colors. An existing name will be replaced.") }
    }
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                SectionEyebrow(title: "YOUR KEYBOARD. YOUR CANVAS.")
                Text("RGB Studio").font(.system(size: 30, weight: .medium, design: .rounded))
                Text("Ant Esports MK1300 V2  ·  61 keys").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Image(systemName: "keyboard").font(.system(size: 25)).foregroundStyle(studioAccent)
                Text("AVAILABLE IN YOUR MENU BAR").font(.system(size: 8, weight: .medium)).tracking(1).foregroundStyle(.secondary)
            }
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 9) {
                Image(systemName: "square.grid.3x3.fill").foregroundStyle(studioAccent)
                Text("MK1300").font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("STUDIO").font(.system(size: 8, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
            }.padding(.top, 8)
            TextField("Find a preset…", text: $model.query).textFieldStyle(.roundedBorder).font(.system(size: 12))
            Picker("Library", selection: $model.savedOnly) { Text("Explore").tag(false); Text("My presets").tag(true) }
                .pickerStyle(.segmented).labelsHidden()
            if !model.savedOnly {
                Picker("Collection", selection: $model.category) {
                    Text("All presets").tag("All presets")
                    ForEach(Set(KicktrollPreset.bundled.map(\.category)).sorted(), id: \.self) { Text($0).tag($0) }
                }.labelsHidden().font(.system(size: 11))
            }
            ScrollView {
                LazyVStack(spacing: 5) {
                    if model.savedOnly {
                        let names = model.presets.keys.sorted().filter { model.query.isEmpty || $0.localizedCaseInsensitiveContains(model.query) }
                        if names.isEmpty { Text("Save a layout to make it yours.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 30) }
                        ForEach(names, id: \.self) { name in
                            presetRow(name, subtitle: "Saved layout", colors: model.presets[name] ?? [:]) {
                                model.load(name, colors: model.presets[name] ?? [:], saved: true)
                            }
                        }
                    } else {
                        if let rs = model.presets["RS"], model.query.isEmpty || "RS".localizedCaseInsensitiveContains(model.query) {
                            presetRow("RS", subtitle: "Your monogram", colors: rs) { model.load("RS", colors: rs, saved: true) }
                        }
                        ForEach(filteredPresets) { preset in
                            presetRow(preset.name, subtitle: preset.category, colors: preset.colors) { model.load(preset.name, colors: preset.colors) }
                        }
                        if filteredPresets.isEmpty { Text("No matching catalog presets.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 20) }
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("140 color stories. One keyboard.").font(.system(size: 10))
                Text("Kicktroll preset collection").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }.padding(18).frame(width: 220).background(studioPanel.opacity(0.6)).disabled(model.isApplying)
    }
    private func presetRow(_ name: String, subtitle: String, colors: [String: String], action: @escaping () -> Void) -> some View {
        let unique = Array(Set(colors.values.filter { $0 != black })).sorted()
        let palette = unique.isEmpty ? [Color.gray.opacity(0.15)] : unique.prefix(5).map(rgbColor)
        return Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7).fill(LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Text(subtitle).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if model.layoutName == name { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(studioAccent) }
            }.padding(8).background(model.layoutName == name ? studioAccent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }
    private var keyboardCard: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionEyebrow(title: "THE CANVAS")
                        Text(model.layoutName).font(.system(size: 20, weight: .medium)).lineLimit(1)
                    }
                    Spacer()
                    Text(model.effect == -1 ? "STATIC LAYOUT" : model.effectName.uppercased())
                        .font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(studioAccent)
                        .padding(8).background(studioAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                }
                VStack(spacing: 5) {
                    ForEach(rows.indices, id: \.self) { index in
                        HStack(spacing: 5) { ForEach(rows[index]) { key in keyButton(key) } }
                    }
                }.padding(10).background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.09), lineWidth: 1))
                    .disabled(model.isApplying || model.effect >= 0)
                HStack {
                    Label("\(model.selected.count) keys selected", systemImage: "cursorarrow.click").font(.system(size: 10))
                    Spacer()
                    Text(model.effect == -1 ? "Click keys to select, then paint." : "Motion runs on the keyboard; preview shows static colors.")
                        .font(.system(size: 9))
                }.foregroundStyle(.secondary)
            }
        }
    }
    private var paintCard: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionEyebrow(title: "MAKE IT YOURS")
                HStack {
                    ColorPicker("Brush", selection: $model.brush, supportsOpacity: false).font(.system(size: 12))
                    Spacer()
                    Text("#\(hexColor(model.brush))").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    ForEach(swatches, id: \.self) { hex in
                        Button { model.brush = rgbColor(hex) } label: {
                            Circle().fill(rgbColor(hex)).frame(width: 19, height: 19)
                                .overlay(Circle().stroke(.white.opacity(hexColor(model.brush) == hex ? 0.9 : 0.15), lineWidth: 2))
                        }.buttonStyle(.plain).accessibilityLabel("Brush #\(hex)")
                    }
                }
                HStack(spacing: 8) {
                    Button("Paint selected") { model.paint(hexColor(model.brush)) }.buttonStyle(.borderedProminent)
                    Button("Turn off") { model.paint(black) }
                }.font(.system(size: 11)).disabled(model.selected.isEmpty)
                HStack(spacing: 16) {
                    Button("Select all") { model.selected = Set(allKeys.map(\.id)) }
                    Button("Deselect") { model.selected.removeAll() }
                    Spacer()
                }.font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.disabled(model.isApplying || model.effect >= 0)
    }
    private var lightingCard: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionEyebrow(title: "SET THE MOOD")
                Picker("Mode", selection: $model.effect) {
                    Text("Static · per-key layout").tag(-1)
                    ForEach(firmwareEffects, id: \.0) { item in Text(item.1).tag(item.0) }
                }.font(.system(size: 11)).labelsHidden()
                BrightnessControl(model: model)
                HStack {
                    if model.effect >= 0 {
                        Picker("Speed", selection: $model.effectSpeed) { ForEach(0...3, id: \.self) { Text(String($0 + 1)).tag($0) } }
                            .font(.system(size: 10))
                    } else { Text("Changes are sent only when you apply.").font(.system(size: 9)).foregroundStyle(.secondary) }
                }.frame(height: 24)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.disabled(model.isApplying)
    }
    private var statusBar: some View {
        HStack(spacing: 12) {
            if model.isApplying { ProgressView().controlSize(.small) }
            else { Image(systemName: model.failed ? "exclamationmark.triangle" : "circle.dotted").foregroundStyle(model.failed ? Color.orange : studioAccent) }
            Text(model.status).font(.system(size: 10)).foregroundStyle(model.failed ? Color.orange : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).lineLimit(3)
            if model.failed { Button { model.copyCommand() } label: { Image(systemName: "doc.on.doc") }.help("Copy terminal command") }
            Button("Save preset…") { model.presetName = model.loadedPreset; model.isSaving = true }
                .disabled(model.isApplying || model.effect >= 0).help("Save the current per-key colors")
            Button { model.apply() } label: { Label("Apply to keyboard", systemImage: "arrow.right") }
                .buttonStyle(.borderedProminent).disabled(model.isApplying).keyboardShortcut(.return, modifiers: .command)
        }.font(.system(size: 11)).padding(.top, 2)
    }
    private func keyButton(_ key: Key) -> some View {
        let hex = model.displayedColor(key)
        let chosen = model.selected.contains(key.id)
        return Button {
            if chosen { model.selected.remove(key.id) } else { model.selected.insert(key.id) }
        } label: {
            VStack(spacing: 6) {
                Text(key.label).font(.system(size: 10, weight: .medium, design: .monospaced)).lineLimit(1)
                Capsule().fill(hex == black ? Color.white.opacity(0.08) : rgbColor(hex)).frame(width: 13, height: 2)
                    .shadow(color: rgbColor(hex).opacity(0.7), radius: 4)
            }
            .foregroundStyle(hex == black ? Color.white.opacity(0.6) : rgbColor(hex).opacity(0.9))
            .frame(width: 47 * key.width - 5, height: 42)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.045)))
            .background(RoundedRectangle(cornerRadius: 5).fill(rgbColor(hex).opacity(hex == black ? 0 : 0.13)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(chosen ? studioAccent : rgbColor(hex).opacity(hex == black ? 0.12 : 0.5), lineWidth: chosen ? 2 : 1))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(key.label)
            .accessibilityValue("\(hex == black ? "Off" : "#\(hex)")\(chosen ? ", selected" : "")")
            .help("\(key.label) · \(hex == black ? "Off" : "#\(hex)")")
    }
}

struct MenuBarControls: View {
    @ObservedObject var model: EditorState
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Image(systemName: "keyboard").font(.system(size: 23)).foregroundStyle(studioAccent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MK1300 RGB").font(.system(size: 15, weight: .semibold))
                    Text(model.effect == -1 ? model.layoutName : model.effectName).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { openWindow(id: "editor"); NSApp.activate(ignoringOtherApps: true) } label: { Image(systemName: "arrow.up.right.square") }.help("Open RGB Studio")
            }
            Divider()
            BrightnessControl(model: model)
            Menu {
                ForEach(model.presets.keys.sorted(), id: \.self) { name in
                    Button(name) { model.load(name, colors: model.presets[name] ?? [:], saved: true); model.apply() }
                }
                if model.presets.isEmpty { Text("Save layouts in RGB Studio first") }
            } label: { Label("Apply a saved preset", systemImage: "square.stack") }
                .disabled(model.isApplying || model.presets.isEmpty)
            HStack {
                Button { model.apply() } label: { Label(model.lightingOff && model.brightness > 0 ? "Restore layout" : "Apply", systemImage: "checkmark") }
                    .buttonStyle(.borderedProminent)
                Button { model.apply(turnOff: true) } label: { Label("Lights off", systemImage: "power") }
            }.disabled(model.isApplying)
            HStack(alignment: .top, spacing: 8) {
                if model.isApplying { ProgressView().controlSize(.small) }
                Text(model.status).font(.system(size: 10)).foregroundStyle(model.failed ? Color.orange : Color.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button("Open RGB Studio") { openWindow(id: "editor"); NSApp.activate(ignoringOtherApps: true) }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.disabled(model.isApplying)
            }.font(.system(size: 11)).buttonStyle(.plain)
        }.padding(20).frame(width: 320).background(studioBackground).preferredColorScheme(.dark).tint(studioAccent)
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
            let args = probeArguments(colors: ["Esc": "FF8040"], effect: -1, brightness: 50, speed: 2)
            guard args.count == 123, args.prefix(3) == ["set", "Esc", "804020"],
                  probeArguments(colors: [:], effect: 6, brightness: 100, speed: 2) == ["effect", "6", "4", "2"],
                  probeArguments(colors: [:], effect: 6, brightness: 0, speed: 2) == ["effect", "0", "0", "2"] else {
                fputs("Shared editor/menu bar command generation failed.\n", stderr)
                exit(1)
            }
            let snapshot = LightingSnapshot(colors: ["Esc": "00D8FF"], effect: -1, speed: 2, name: "Saved layout")
            guard let data = try? JSONEncoder().encode(snapshot),
                  let restored = try? JSONDecoder().decode(LightingSnapshot.self, from: data),
                  restored.colors == snapshot.colors, restored.name == snapshot.name else {
                fputs("Layout persistence validation failed.\n", stderr)
                exit(1)
            }
            print("Bundle verified: 61 keys, 140 presets, brightness, shared menu/editor commands, and layout persistence.")
            return
        }
        KeyboardEditorApp.main()
    }
}

@MainActor
final class StudioAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            let bars: [(CGFloat, CGFloat, NSColor)] = [
                (2, 10, NSColor(srgbRed: 0, green: 0.68, blue: 0.88, alpha: 1)),
                (8, 16, NSColor(srgbRed: 0.95, green: 0.18, blue: 0.48, alpha: 1)),
                (14, 12, NSColor(srgbRed: 0.48, green: 0.76, blue: 0.16, alpha: 1))
            ]
            for (x, height, color) in bars {
                color.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: (18 - height) / 2, width: 4, height: height),
                             xRadius: 2, yRadius: 2).fill()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "MK1300 RGB Studio"
        return image
    }()
}

struct KeyboardEditorApp: App {
    @NSApplicationDelegateAdaptor(StudioAppDelegate.self) private var appDelegate
    @StateObject private var model = EditorState()
    var body: some Scene {
        Window("MK1300 RGB Studio", id: "editor") { Editor(model: model) }
            .windowResizability(.contentSize)
        MenuBarExtra {
            MenuBarControls(model: model)
        } label: {
            Image(nsImage: MenuBarIcon.image).renderingMode(.original)
                .accessibilityLabel("MK1300 RGB Studio")
        }
            .menuBarExtraStyle(.window)
    }
}
