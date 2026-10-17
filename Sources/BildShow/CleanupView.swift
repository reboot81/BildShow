import SwiftUI
import ImageIO
import BildShowCore

struct CleanupView: View {
    @ObservedObject var store: AppStore
    let presetID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var selection = Set<String>()
    @State private var confirm = false
    @State private var working = false
    @State private var report = ""
    var scopedPresets: [Preset] { store.presets.filter { presetID == nil || $0.id == presetID } }
    var paths: [String] { Array(Set(scopedPresets.flatMap { Array($0.markedPaths) })).sorted() }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Städa markerade bilder", "Clean marked images")).font(.title2.bold())
                    Text(L("Granska originalen innan du flyttar dem till Papperskorgen.", "Review originals before moving them to Trash.")).foregroundStyle(.secondary)
                }; Spacer()
                Button(L("Stäng", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                Button(L("Markera alla", "Select all")) { selection = Set(paths) }
                Button(L("Avmarkera alla", "Deselect all")) { selection = [] }
                Spacer(); Text("\(selection.count) / \(paths.count)").monospacedDigit()
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                    ForEach(paths, id: \.self) { path in
                        VStack(alignment: .leading, spacing: 8) {
                            CleanupThumbnail(path: path, folders: scopedPresets.flatMap(\.folders)).frame(height: 120).frame(maxWidth: .infinity).background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                            Toggle(URL(fileURLWithPath: path).lastPathComponent, isOn: Binding(get: { selection.contains(path) }, set: { if $0 { selection.insert(path) } else { selection.remove(path) } })).lineLimit(1)
                            HStack {
                                Button(L("Visa i Finder", "Reveal")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                                Spacer()
                                Button { unmark([path]) } label: { Image(systemName: "arrow.uturn.backward") }.help(L("Ta bort städmarkeringen", "Remove cleanup mark"))
                            }.font(.caption)
                        }.padding(10).background(.background, in: RoundedRectangle(cornerRadius: 12)).help(path)
                    }
                }
                if paths.isEmpty { ContentUnavailableView(L("Inga markerade bilder", "No marked images"), systemImage: "checkmark.circle", description: Text(L("Markera bilder under ett bildspel för att granska dem här.", "Mark images during a slideshow to review them here."))) }
            }
            if !report.isEmpty { Text(report).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                Button(L("Ångra valda markeringar", "Unmark selected")) { unmark(selection) }.disabled(selection.isEmpty || working)
                Spacer()
                if working { ProgressView().controlSize(.small) }
                Button(L("Flytta valda till Papperskorgen…", "Move selected to Trash…"), role: .destructive) { confirm = true }.disabled(selection.isEmpty || working)
            }
        }.padding(24).frame(width: 880, height: 650)
            .confirmationDialog(L("Originalfilerna flyttas till Papperskorgen och försvinner från alla presets som använder dem.", "The original files will move to Trash and disappear from every preset that uses them."), isPresented: $confirm) {
                Button(L("Flytta till Papperskorgen", "Move to Trash"), role: .destructive) { trash() }
            }
    }
    func unmark(_ paths: Set<String>) {
        for preset in scopedPresets { store.update(preset.id) { $0.markedPaths.subtract(paths) } }
        selection.subtract(paths)
    }
    func trash() {
        working = true
        let selected = selection, folders = scopedPresets.flatMap(\.folders)
        let records = store.indexes.values.flatMap(\.images)
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (Set<String>, [String]) in
                let access = ScopedAccess(folders)
                var removed = Set<String>(), errors: [String] = []
                for path in selected {
                    do {
                        let url = URL(fileURLWithPath: path)
                        guard let expected = records.first(where: { $0.path == path }) else { throw NSError(domain: "BildShow", code: 1, userInfo: [NSLocalizedDescriptionKey: L("Uppdatera presetens bildlista först.", "Refresh the preset's image list first.")]) }
                        let now = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
                        guard now.isRegularFile == true, Int64(now.fileSize ?? -1) == expected.bytes, abs((now.contentModificationDate ?? .distantPast).timeIntervalSince(expected.modified)) < 0.01 else {
                            throw NSError(domain: "BildShow", code: 2, userInfo: [NSLocalizedDescriptionKey: L("Filen har ändrats. Uppdatera och granska den igen.", "The file has changed. Refresh and review it again.")])
                        }
                        try FileManager.default.trashItem(at: url, resultingItemURL: nil); removed.insert(path)
                    } catch { errors.append("\(URL(fileURLWithPath: path).lastPathComponent): \(error.localizedDescription)") }
                }
                withExtendedLifetime(access) {}
                return (removed, errors)
            }.value
            for preset in store.presets {
                store.update(preset.id) { $0.markedPaths.subtract(outcome.0) }
                if var index = store.indexes[preset.id] {
                    index.images.removeAll { outcome.0.contains($0.path) }; store.indexes[preset.id] = index
                    store.write(index, to: store.cache.appendingPathComponent("\(preset.id).json"))
                }
            }
            selection.subtract(outcome.0); working = false
            report = "\(outcome.0.count) " + L("flyttade till Papperskorgen.", "moved to Trash.") + (outcome.1.isEmpty ? "" : "\n" + outcome.1.joined(separator: "\n"))
        }
    }
}

struct CleanupThumbnail: View {
    let path: String
    let folders: [FolderReference]
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary) }
        }.task(id: path) {
            let cg = await Task.detached(priority: .utility) { () -> CGImage? in
                let access = ScopedAccess(folders); defer { withExtendedLifetime(access) {} }
                guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 320, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
            }.value
            if let cg, !Task.isCancelled { image = NSImage(cgImage: cg, size: .zero) }
        }
    }
}
