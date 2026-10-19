import SwiftUI
import BildShowCore

struct PlaybackSettingsEditor: View {
    @Binding var values: [String: SettingValue]
    @Binding var rules: [SizeRule]?
    @Binding var portrait: String?
    @Binding var landscape: String?
    var inherited: Preferences
    var isPreset: Bool
    var demo: () -> Void
    var body: some View {
        Form {
            Section(L("Uppspelning", "Playback")) {
                ForEach([Setting.fullscreen, .manual, .random, .ending, .interval, .transition, .transitionDuration], id: \.self) { settingRow($0) }
                Text(L("Bildtiden inkluderar övergången. Övergången begränsas till högst halva bildtiden.", "The interval includes the transition. Transitions are limited to half the interval."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Bildvisning", "Image display")) {
                ForEach([Setting.layout, .cropLimit, .placement, .cropAnchor, .background, .feather, .filenameAlways], id: \.self) { settingRow($0) }
                orientationPicker(L("Stående bilder", "Portrait images"), value: $portrait)
                orientationPicker(L("Liggande bilder", "Landscape images"), value: $landscape)
                Text(L("Bildens proportioner bevaras alltid. Fyll, bredd och höjd kan beskära bilden.", "Aspect ratio is always preserved. Fill, width and height modes can crop the image."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Urval och cache", "Selection and cache")) {
                ForEach([Setting.includeGIF, .minShort, .minLong, .prefetch], id: \.self) { settingRow($0) }
                Text(L("WebP ingår. Måttgränser utesluter bilder utan att ändra originalen.", "WebP is included. Dimension limits exclude images without changing the originals."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Storleksberoende behandling · 4K", "Size-based processing · 4K")) {
                if isPreset {
                    Toggle(L("Egna storleksregler", "Custom size rules"), isOn: Binding(get: { rules != nil }, set: { rules = $0 ? inherited.rules : nil }))
                }
                Text(L("Reglerna väljs efter nödvändig förstoring före maxgränsen, i verkliga skärmpixlar. Utgångspunkt: 3840 × 2160.", "Rules use the required enlargement before the cap, in physical display pixels. Baseline: 3840 × 2160."))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array((rules ?? inherited.rules).enumerated()), id: \.element.id) { index, rule in
                    DisclosureGroup(ruleTitle(rule.id)) {
                        HStack {
                            Text(L("Max förstoring", "Maximum enlargement"))
                            Spacer()
                            TextField("", value: ruleBinding(index, \.maxScale), format: .number.precision(.fractionLength(0...2)))
                                .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 72)
                            Text("×")
                            Stepper("", value: ruleBinding(index, \.maxScale), in: 1...8, step: 0.25).labelsHidden()
                        }
                        if rule.id != "small" {
                            HStack {
                                Text(L("Klassens övre skalfaktor", "Class upper scale factor")); Spacer()
                                TextField("", value: ruleBinding(index, \.upperScale), format: .number.precision(.fractionLength(0...2)))
                                    .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 72)
                                Stepper("", value: ruleBinding(index, \.upperScale), in: 0.25...8, step: 0.25).labelsHidden()
                            }
                        }
                        Picker(L("Skalningsmetod", "Resampling"), selection: methodBinding(index)) {
                            Text("Lanczos").tag("lanczos"); Text(L("Bikubisk", "Bicubic")).tag("bicubic"); Text(L("Bilinjär (snabb)", "Bilinear (fast)")).tag("linear")
                        }
                        HStack {
                            Text(L("Skärpning", "Sharpening")); Slider(value: ruleBinding(index, \.sharpening), in: 0...0.8)
                            TextField("", value: ruleBinding(index, \.sharpening), format: .number.precision(.fractionLength(2)))
                                .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 64)
                        }
                        HStack {
                            Text(L("Kanttoning (%)", "Edge feather (%)")); Slider(value: ruleBinding(index, \.featherPercent), in: 0...8)
                            TextField("", value: ruleBinding(index, \.featherPercent), format: .number.precision(.fractionLength(1)))
                                .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 64)
                        }
                    }.disabled(isPreset && rules == nil)
                }
            }
            Section {
                Button(action: demo) { Label(L("Demo med dessa inställningar", "Demo with these settings"), systemImage: "play.rectangle") }
                Text(L("Demon använder samma bildmotor och påverkar inte en presets position.", "The demo uses the same image renderer without changing a preset's playback position."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    func ruleTitle(_ id: String) -> String {
        switch id {
        case "reduce": return L("Stor bild · förminskning", "Large image · downscaling")
        case "near": return L("Nästan skärmstor", "Near display size")
        case "medium": return L("Mellanstor bild", "Medium image")
        default: return L("Liten bild", "Small image")
        }
    }
    func value(_ key: Setting) -> SettingValue { values[key.rawValue] ?? inherited[key] }
    @ViewBuilder func settingRow(_ key: Setting) -> some View {
        HStack {
            if case .bool = key.initial {
                Toggle(key.title, isOn: Binding(get: { value(key).bool }, set: { values[key.rawValue] = .bool($0) }))
            } else if !key.options.isEmpty {
                Picker(key.title, selection: Binding(get: { value(key).text }, set: { values[key.rawValue] = .text($0) })) {
                    ForEach(key.options, id: \.0) { Text($0.1).tag($0.0) }
                }
            } else {
                Text(key.title); Spacer()
                TextField("", value: numberBinding(key), format: .number.precision(.fractionLength(0...2)))
                    .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 85)
                Stepper("", value: numberBinding(key), in: key.range, step: numberStep(key)).labelsHidden()
            }
            if isPreset {
                Button { values.removeValue(forKey: key.rawValue) } label: {
                    Image(systemName: values[key.rawValue] == nil ? "link" : "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help(values[key.rawValue] == nil
                    ? L("Länkad till programmets standardvärde. Ändra kontrollen för att skapa ett eget värde för preseten.", "Linked to the application default. Change the control to create a preset-specific value.")
                    : L("Återställ länken till programmets standardvärde", "Restore the link to the application default"))
            }
        }
    }
    func numberBinding(_ key: Setting) -> Binding<Double> {
        Binding(
            get: { value(key).number },
            set: { number in
                let finite = number.isFinite ? number : key.initial.number
                values[key.rawValue] = .number(min(key.range.upperBound, max(key.range.lowerBound, finite)))
            }
        )
    }
    func numberStep(_ key: Setting) -> Double {
        switch key {
        case .interval, .transitionDuration: return 0.25
        case .cropLimit, .prefetch, .minShort, .minLong: return 1
        default: return 0.1
        }
    }
    func orientationPicker(_ title: String, value: Binding<String?>) -> some View {
        Picker(title, selection: Binding(get: { value.wrappedValue ?? "inherit" }, set: { value.wrappedValue = $0 == "inherit" ? nil : $0 })) {
            Text(L("Följ bildanpassning / standard", "Follow layout / default")).tag("inherit")
            ForEach(layoutOptions, id: \.0) { Text($0.1).tag($0.0) }
        }
    }
    func ruleBinding(_ index: Int, _ path: WritableKeyPath<SizeRule, Double>) -> Binding<Double> {
        Binding(get: { (rules ?? inherited.rules)[index][keyPath: path] }, set: { value in
            var copy = rules ?? inherited.rules
            copy[index][keyPath: path] = max(0, value.isFinite ? value : 0)
            rules = copy
        })
    }
    func methodBinding(_ index: Int) -> Binding<String> {
        Binding(get: { (rules ?? inherited.rules)[index].method }, set: { value in var copy = rules ?? inherited.rules; copy[index].method = value; rules = copy })
    }
}

struct SettingsView: View {
    @ObservedObject var store: AppStore
    var demo: (Preferences) -> Void
    var body: some View {
        TabView {
            PlaybackSettingsEditor(values: $store.preferences.values,
                rules: Binding(get: { store.preferences.rules }, set: { store.preferences.rules = $0 ?? SizeRule.defaults }),
                portrait: Binding(get: { store.preferences.portraitLayout }, set: { store.preferences.portraitLayout = $0 ?? "inherit" }),
                landscape: Binding(get: { store.preferences.landscapeLayout }, set: { store.preferences.landscapeLayout = $0 ?? "inherit" }),
                inherited: Preferences(), isPreset: false, demo: { demo(store.preferences) })
                .tabItem { Label(L("Bildspel", "Slideshow"), systemImage: "photo.on.rectangle") }
            ShortcutSettings(store: store).tabItem { Label(L("Tangentbord och mus", "Keyboard and mouse"), systemImage: "keyboard") }
            Form {
                Picker(L("Starta preset när appen öppnas", "Start preset when the app opens"), selection: $store.preferences.autostartPreset) {
                    Text(L("Visa huvudfönstret", "Show main window")).tag(nil as UUID?)
                    ForEach(store.presets) { Text($0.name).tag(Optional($0.id)) }
                }
                Text(L("Inställningar är standardvärden. En preset kan ändra enskilda värden och fortsätter ärva övriga.", "Settings are defaults. A preset can override individual values and keeps inheriting the rest."))
            }.formStyle(.grouped).tabItem { Label(L("Allmänt", "General"), systemImage: "gearshape") }
        }.padding(10).frame(width: 680, height: 740)
            .onChange(of: store.preferences) { _, _ in store.savePreferences() }
    }
}

struct ShortcutSettings: View {
    @ObservedObject var store: AppStore
    @State private var recording: PlayerAction?
    @State private var monitor: Any?
    @State private var message = ""
    var body: some View {
        Form {
            Section(L("Kortkommandon i bildspelet", "Slideshow shortcuts")) {
                ForEach(PlayerAction.allCases) { action in
                    HStack {
                        Text(action.title); Spacer()
                        Button(recording == action ? L("Tryck en tangent…", "Press a key…") : (store.preferences.shortcuts[action.rawValue] ?? action.initial).label) { recording = action }
                            .frame(width: 160)
                        Button { store.preferences.shortcuts.removeValue(forKey: action.rawValue) } label: { Image(systemName: "arrow.uturn.backward") }.buttonStyle(.borderless)
                    }
                }
                if !message.isEmpty { Text(message).foregroundStyle(.orange).font(.caption) }
                Text(L("Genvägarna gäller endast i bildspelsfönstret. Esc avslutar alltid bildspelet och avbryter inspelning.", "Shortcuts only apply in the slideshow window. Esc always ends playback and cancels recording."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Mus", "Mouse")) {
                ForEach([("left", L("Vänsterklick", "Left click")), ("right", L("Högerklick", "Right click")), ("middle", L("Mittklick", "Middle click")), ("scrollUp", L("Rulla upp", "Scroll up")), ("scrollDown", L("Rulla ner", "Scroll down"))], id: \.0) { key, title in
                    Picker(title, selection: Binding(get: { store.preferences.mouse[key] ?? "none" }, set: { store.preferences.mouse[key] = $0 })) {
                        Text(L("Ingen åtgärd", "No action")).tag("none")
                        Text(L("Meny", "Menu")).tag("menu")
                        ForEach(PlayerAction.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                }
            }
        }.formStyle(.grouped)
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard let action = recording else { return event }
                if event.keyCode == 53 { recording = nil; return nil }
                let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
                let symbols = (modifiers.contains(.control) ? "⌃" : "") + (modifiers.contains(.option) ? "⌥" : "") + (modifiers.contains(.shift) ? "⇧" : "") + (modifiers.contains(.command) ? "⌘" : "")
                let special: [UInt16: String] = [49: "Space", 123: "←", 124: "→", 125: "↓", 126: "↑", 36: "↩", 48: "⇥", 51: "⌫"]
                let binding = KeyBinding(event.keyCode, modifiers: modifiers.rawValue, label: symbols + (special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "?"))
                if let duplicate = PlayerAction.allCases.first(where: { other in
                    let existing = store.preferences.shortcuts[other.rawValue] ?? other.initial
                    return other != action && existing.code == binding.code && existing.modifiers == binding.modifiers
                }) { message = L("Används redan för: ", "Already used by: ") + duplicate.title; return nil }
                store.preferences.shortcuts[action.rawValue] = binding; recording = nil; message = ""
                return nil
            }
        }.onDisappear { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; recording = nil }
    }
}
