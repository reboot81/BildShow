import SwiftUI
import UniformTypeIdentifiers
import BildShowCore

@MainActor final class AppStore: ObservableObject {
    @Published var presets: [Preset] = []
    @Published var preferences = Preferences()
    @Published var indexes: [UUID: ScanResult] = [:]
    @Published var scanning: Set<UUID> = []
    @Published var logs: [String] = []
    let base: URL
    let cache: URL
    private let writer = DispatchQueue(label: "se.bosaurage.BildShow.persistence", qos: .utility)
    private var scanTasks: [UUID: Task<ScanResult, Never>] = [:]
    private var revisions: [UUID: UUID] = [:]
    init() {
        base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BildShow")
        cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("BildShow")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: base.appendingPathComponent("preferences.json")), let prefs = try? JSONDecoder().decode(Preferences.self, from: data) { preferences = prefs }
        let folders = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
        for folder in folders where folder.hasDirectoryPath {
            if let data = try? Data(contentsOf: folder.appendingPathComponent("preset.json")), let preset = try? JSONDecoder().decode(Preset.self, from: data) {
                presets.append(preset)
                if let data = try? Data(contentsOf: cache.appendingPathComponent("\(preset.id).json")), let index = try? JSONDecoder().decode(ScanResult.self, from: data) { indexes[preset.id] = index }
            }
        }
        if let data = try? Data(contentsOf: base.appendingPathComponent("order.json")), let ids = try? JSONDecoder().decode([UUID].self, from: data) {
            presets.sort { (ids.firstIndex(of: $0.id) ?? Int.max) < (ids.firstIndex(of: $1.id) ?? Int.max) }
        } else { presets.sort { $0.name < $1.name } }
    }
    func write<T: Encodable & Sendable>(_ value: T, to url: URL) {
        writer.async {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(value).write(to: url, options: .atomic)
            } catch { Task { @MainActor in self.log(error.localizedDescription) } }
        }
    }
    func savePreferences() { write(preferences, to: base.appendingPathComponent("preferences.json")) }
    func save(_ preset: Preset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) { presets[index] = preset } else { presets.append(preset) }
        write(preset, to: base.appendingPathComponent(preset.id.uuidString).appendingPathComponent("preset.json"))
        saveOrder()
    }
    func update(_ id: UUID, _ change: (inout Preset) -> Void) {
        guard var value = presets.first(where: { $0.id == id }) else { return }
        change(&value); save(value)
    }
    func saveOrder() { write(presets.map(\.id), to: base.appendingPathComponent("order.json")) }
    func order(for id: UUID) -> [String] {
        let url = base.appendingPathComponent(id.uuidString).appendingPathComponent("sequence.json")
        return (try? JSONDecoder().decode([String].self, from: Data(contentsOf: url))) ?? []
    }
    func saveSequence(_ value: [String], id: UUID) { write(value, to: base.appendingPathComponent(id.uuidString).appendingPathComponent("sequence.json")) }
    func flush() { writer.sync {} }
    func imageCount(_ preset: Preset) -> Int { indexes[preset.id]?.images.filter { $0.included(in: preferences.resolved(for: preset)) }.count ?? 0 }
    func refresh(_ preset: Preset) async -> ScanResult {
        if let task = scanTasks[preset.id] { return await task.value }
        scanning.insert(preset.id)
        let token = UUID(); revisions[preset.id] = token
        let task = Task.detached(priority: .utility) { Catalog.scan(preset.folders, sort: preset.sort) }
        scanTasks[preset.id] = task
        let result = await task.value
        if revisions[preset.id] == token {
            indexes[preset.id] = result; scanning.remove(preset.id); scanTasks[preset.id] = nil
            write(result, to: cache.appendingPathComponent("\(preset.id).json"))
        }
        return result
    }
    func invalidate(_ id: UUID) {
        scanTasks[id]?.cancel(); scanTasks[id] = nil; revisions[id] = UUID(); indexes[id] = nil; scanning.remove(id)
    }
    func remove(_ preset: Preset) {
        invalidate(preset.id); presets.removeAll { $0.id == preset.id }; saveOrder()
        let url = base.appendingPathComponent(preset.id.uuidString)
        writer.async { try? FileManager.default.removeItem(at: url) }
    }
    func duplicate(_ preset: Preset) {
        var copy = preset; copy.id = UUID(); copy.name += L(" – kopia", " – copy"); copy.lastPath = nil
        save(copy)
        if let index = indexes[preset.id] { indexes[copy.id] = index; write(index, to: cache.appendingPathComponent("\(copy.id).json")) }
    }
    func log(_ message: String) {
        logs.append("\(Date().formatted(date: .omitted, time: .standard))  \(message)")
        if logs.count > 300 { logs.removeFirst(logs.count - 300) }
    }
    func exportPreset(_ preset: Preset) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = preset.name + ".bildshow.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var copy = preset
        copy.folders = copy.folders.map { var folder = $0; folder.bookmark = nil; return folder }
        do { try JSONEncoder().encode(copy).write(to: url, options: .atomic) } catch { showError(error.localizedDescription) }
    }
    func importPreset() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var preset = try JSONDecoder().decode(Preset.self, from: Data(contentsOf: url))
            preset.id = UUID(); preset.markedPaths = []; preset.lastPath = nil
            preset.folders = preset.folders.map { var folder = $0; folder.bookmark = nil; return folder }
            save(preset)
            log(L("Importerad preset: ge mapparna åtkomst i redigeraren.", "Imported preset: grant folder access in the editor."))
        } catch { showError(error.localizedDescription) }
    }
}
