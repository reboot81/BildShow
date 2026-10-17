import SwiftUI
import BildShowCore

@main struct BildShowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store: AppStore
    @StateObject private var player: PlayerCoordinator
    @Environment(\.openWindow) private var openWindow
    init() {
        let store = AppStore()
        _store = StateObject(wrappedValue: store)
        _player = StateObject(wrappedValue: PlayerCoordinator(store: store))
        AppDelegate.store = store
    }
    var body: some Scene {
        WindowGroup("BildShow") {
            MainView(store: store, player: player).frame(minWidth: 720, minHeight: 500)
        }.defaultSize(width: 980, height: 680)
        .commands {
            CommandGroup(replacing: .appInfo) { Button(L("Om BildShow", "About BildShow")) { openWindow(id: "about") } }
            CommandGroup(after: .importExport) { Button(L("Importera preset…", "Import preset…")) { store.importPreset() } }
            CommandGroup(replacing: .help) { Button(L("Visa händelselogg", "Show event log")) { openWindow(id: "log") } }
        }
        Settings { SettingsView(store: store, demo: player.demo) }
        Window(L("Om BildShow", "About BildShow"), id: "about") { AboutView(store: store).frame(width: 650, height: 590) }.windowResizability(.contentSize)
        Window(L("Händelselogg", "Event log"), id: "log") {
            VStack(alignment: .leading) {
                HStack { Text(L("Överhoppade bilder och händelser", "Skipped images and events")).font(.headline); Spacer(); Button(L("Rensa", "Clear")) { store.logs = [] } }
                ScrollView { Text(store.logs.isEmpty ? L("Inga händelser ännu.", "No events yet.") : store.logs.joined(separator: "\n")).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            }.padding(20).frame(minWidth: 600, minHeight: 400)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var store: AppStore?
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationWillTerminate(_ notification: Notification) { Self.store?.flush() }
}

struct MainView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var player: PlayerCoordinator
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var editing: Preset?
    @State private var cleanup = false
    @State private var cleanupID: UUID?
    @State private var deleting: Preset?
    @State private var dragging: UUID?
    @State private var search = ""
    @State private var appeared = false
    private var filtered: [Preset] { store.presets.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("Dina bildspel", "Your slideshows")).font(.largeTitle.weight(.bold))
                    Text(L("Samla mappar. Välj en preset. Låt bilderna ta plats.", "Gather folders. Choose a preset. Let your images take the stage.")).foregroundStyle(.secondary)
                }
                Spacer()
                if player.starting { ProgressView().controlSize(.small) }
            }.padding(28)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 320), spacing: 16)], spacing: 16) {
                    Button { editing = Preset() } label: {
                        VStack(spacing: 15) {
                            Image(systemName: "plus.circle.fill").font(.system(size: 38, weight: .light)).foregroundStyle(.tint)
                            Text(L("Ny preset", "New preset")).font(.headline)
                            Text(L("Lägg till bildmappar", "Add image folders")).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).frame(height: 150)
                            .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentColor.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                    }.buttonStyle(.plain)
                    ForEach(filtered) { preset in
                        VStack(spacing: 0) {
                            Button { player.start(preset) } label: {
                                VStack(spacing: 12) {
                                    HStack { Image(systemName: "play.fill").font(.title2).foregroundStyle(.tint); Spacer(); Image(systemName: "rectangle.stack").foregroundStyle(.tertiary) }
                                    Text(preset.name).font(.title3.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading).lineLimit(2)
                                }.padding(20).frame(maxWidth: .infinity).frame(height: 108)
                            }.buttonStyle(.plain).disabled(player.starting)
                            Divider()
                            HStack {
                                Text("\(preset.folders.count) / \(store.imageCount(preset))").monospacedDigit()
                                    .help(L("Mappar / bilder", "Folders / images"))
                                if store.scanning.contains(preset.id) { ProgressView().controlSize(.mini) }
                                Spacer()
                                Menu { presetMenu(preset) } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24)
                            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).frame(height: 42)
                        }.background(.background, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08)))
                            .contextMenu { presetMenu(preset) }
                            .onDrag { dragging = preset.id; return NSItemProvider(object: preset.id.uuidString as NSString) }
                            .onDrop(of: [.text], isTargeted: nil) { _ in
                                guard let dragging, let from = store.presets.firstIndex(where: { $0.id == dragging }), let to = store.presets.firstIndex(where: { $0.id == preset.id }), from != to else { return false }
                                let value = store.presets.remove(at: from); store.presets.insert(value, at: to); store.saveOrder(); self.dragging = nil; return true
                            }
                    }
                }.padding(.horizontal, 28).padding(.bottom, 28)
                if store.presets.isEmpty {
                    VStack(spacing: 10) {
                        Text(L("Bilderna stannar i dina mappar", "Your images stay in their folders")).font(.headline)
                        Text(L("En preset kommer ihåg urvalet, inställningarna och var du slutade.\nHögerklicka på en skapad preset för att redigera den.", "A preset remembers your selection, settings, and playback position.\nRight-click a saved preset to edit it."))
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding(.top, 30)
                }
            }
            Divider()
            HStack {
                Label("\(store.presets.count) " + L("presets", "presets"), systemImage: "rectangle.stack").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !store.logs.isEmpty { Button { openWindow(id: "log") } label: { Label("\(store.logs.count)", systemImage: "list.bullet.rectangle") }.buttonStyle(.borderless) }
                Text(L("Apple Silicon · Lokala bilder", "Apple Silicon · Local images")).font(.caption).foregroundStyle(.tertiary)
            }.padding(.horizontal, 24).padding(.vertical, 12)
        }.background(Color(nsColor: .windowBackgroundColor))
            .toolbar {
                ToolbarItem { Button { store.importPreset() } label: { Label(L("Importera", "Import"), systemImage: "square.and.arrow.down") } }
                ToolbarItem { Button { cleanupID = nil; cleanup = true } label: { Label(L("Städa", "Cleanup"), systemImage: "trash") } }
                ToolbarItem { Button { openSettings() } label: { Label(L("Inställningar", "Settings"), systemImage: "gearshape") } }
            }.searchable(text: $search, prompt: L("Sök presets", "Search presets"))
            .sheet(item: $editing) { preset in PresetEditor(store: store, preset: preset, demo: player.demo, onSave: store.save) }
            .sheet(isPresented: $cleanup) { CleanupView(store: store, presetID: cleanupID) }
            .confirmationDialog(L("Ta bort preset? Bilderna behålls.", "Delete preset? Your images are kept."), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button(L("Ta bort preset", "Delete preset"), role: .destructive) { if let deleting { store.remove(deleting) }; deleting = nil }
            }
            .onAppear {
                guard !appeared else { return }; appeared = true
                if let id = store.preferences.autostartPreset, let preset = store.presets.first(where: { $0.id == id }) { player.start(preset) }
            }
    }
    @ViewBuilder func presetMenu(_ preset: Preset) -> some View {
        Button(L("Redigera / byt namn…", "Edit / rename…")) { editing = preset }
        Button(L("Börja om", "Start over")) { player.start(preset, restart: true) }
        Button(L("Duplicera", "Duplicate")) { store.duplicate(preset) }
        Button(L("Uppdatera bildlista", "Refresh image list")) { Task { _ = await store.refresh(preset) } }
        Button(L("Kontrollera bilder…", "Check images…")) { validate(preset) }
        Button(L("Städa markerade bilder…", "Clean marked images…")) { cleanupID = preset.id; cleanup = true }
        Button(L("Exportera…", "Export…")) { store.exportPreset(preset) }
        Divider()
        Button(L("Ta bort preset…", "Delete preset…"), role: .destructive) { deleting = preset }
    }
    func validate(_ preset: Preset) {
        Task {
            let result = await store.refresh(preset)
            let access = ScopedAccess(preset.folders)
            let settings = store.preferences.resolved(for: preset)
            var failed = result.errors.count
            for item in result.images where item.included(in: settings) {
                do { _ = try await ImagePipeline.shared.load(item, settings: settings, size: CGSize(width: 3840, height: 2160)) }
                catch { failed += 1; store.log("\(item.path): \(error.localizedDescription)") }
            }
            withExtendedLifetime(access) {}
            showError(L("Kontrollen är klar. ", "Check complete. ") + "\(failed) " + L("bilder kunde inte läsas. Detaljer finns i händelseloggen.", "images could not be read. Details are in the event log."))
        }
    }
}

struct AboutView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 80, height: 80)
                VStack(alignment: .leading) { Text("BildShow").font(.largeTitle.bold()); Text("Version 0.1.0 (1)").foregroundStyle(.secondary) }
            }
            Text(L("BildShow visar dina bilder i lugna, flytande bildspel. Samla flera mappar i presets och anpassa visningen för föreläsningar, mässor eller en stund med dina bilder.", "BildShow presents your images in calm, fluid slideshows. Collect folders into presets and tailor playback for lectures, exhibitions, or time with your photographs."))
            GroupBox(L("Integritet", "Privacy")) {
                Text(L("BildShow arbetar lokalt. Bilder och filnamn skickas inte till någon server. Appen använder mappar du ger åtkomst till. Original flyttas till Papperskorgen endast genom städfunktionen efter ditt val.", "BildShow works locally. Images and filenames are not sent to any server. The app uses folders you authorize. Originals are moved to Trash only through the cleanup function after your selection."))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox(L("Relevanta filer", "Relevant files")) {
                VStack(alignment: .leading, spacing: 7) { Text("App: \(Bundle.main.bundlePath)"); Text(L("Inställningar: ", "Settings: ") + store.base.path); Text("Cache: \(store.cache.path)") }
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox(L("Teknisk status", "Technical status")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("macOS 14+ · Apple Silicon · Image I/O · Core Image · Metal")
                    Text("GPU: \(ImagePipeline.shared.device.name)")
                    Text(L("Demoporträttet är AI-genererat. Ingen AI används vid bildvisning.", "The demo portrait is AI-generated. Slideshow playback does not use AI."))
                }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack { Text("© 2026 Bo Saurage").foregroundStyle(.secondary); Spacer(); Link("GitHub", destination: URL(string: "https://github.com/reboot81/BildShow")!) }
            Spacer(minLength: 0)
        }.padding(28)
    }
}
