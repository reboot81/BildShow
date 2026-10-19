import SwiftUI
import UniformTypeIdentifiers
import BildShowCore

struct PresetEditor: View {
    @ObservedObject var store: AppStore
    @State var preset: Preset
    var demo: (Preferences) -> Void
    var onSave: (Preset) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var roots: [FolderReference] = []
    @State private var access: ScopedAccess?
    @State private var selectedFolders: Set<UUID> = []
    @State private var history: [[FolderReference]] = []
    @State private var editorSection = "folders"
    @State private var counting = false
    @State private var countResult = ScanResult()
    @State private var countTask: Task<Void, Never>?
    @State private var monitor: Any?
    @State private var dragging: UUID?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "rectangle.stack.badge.plus").font(.title2).foregroundStyle(.tint)
                TextField(L("Presetens namn", "Preset name"), text: $preset.name).textFieldStyle(.roundedBorder).font(.title3)
                Picker("", selection: $editorSection) {
                    Label(L("Mappar", "Folders"), systemImage: "folder").tag("folders")
                    Label(L("Bildspelsinställningar", "Slideshow settings"), systemImage: "slider.horizontal.3").tag("settings")
                }
                .pickerStyle(.segmented)
                .frame(width: 390)
            }.fixedSize(horizontal: false, vertical: true).padding(20)
            if editorSection == "settings" {
                PlaybackSettingsEditor(values: $preset.overrides, rules: $preset.rules, portrait: $preset.portraitLayout, landscape: $preset.landscapeLayout,
                                       inherited: store.preferences, isPreset: true, demo: { demo(store.preferences.resolved(for: preset)) })
                HStack {
                    Picker(L("Ordning utan slumpning", "Order without shuffle"), selection: $preset.sort) {
                        Text(L("Filnamn", "Filename")).tag("name"); Text(L("Ändringsdatum", "Modification date")).tag("date")
                    }
                    Picker(L("Visningsskärm", "Display"), selection: $preset.displayID) {
                        Text(L("Där appen finns", "Current app display")).tag(nil as UInt32?)
                        ForEach(NSScreen.screens, id: \.localizedName) { screen in Text(screen.localizedName).tag((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value) }
                    }
                }.padding()
            } else {
                HSplitView {
                    selectedFoldersPane
                    folderBrowserPane
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            Divider()
            HStack {
                Button { undo() } label: { Label(L("Ångra", "Undo"), systemImage: "arrow.uturn.backward") }.disabled(history.isEmpty).keyboardShortcut("z", modifiers: .command)
                if counting { ProgressView().controlSize(.small) }
                let included = countResult.images.filter { $0.included(in: store.preferences.resolved(for: preset)) }.count
                Text("\(preset.folders.count) " + L("mappar", "folders") + " · \(included) " + L("bilder", "images") + (countResult.images.count > included ? " · \(countResult.images.count - included) " + L("uteslutna", "excluded") : ""))
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                if !countResult.unavailableFolders.isEmpty { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).help(countResult.unavailableFolders.joined(separator: "\n")) }
                Spacer()
                Button(L("Avbryt", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Spara preset", "Save preset")) {
                    preset.name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.invalidate(preset.id); onSave(preset); dismiss()
                    Task { _ = await store.refresh(preset) }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || preset.folders.isEmpty)
            }.padding(16)
        }.frame(width: 1400, height: 966)
            .onAppear {
                roots = browserRoots(); access = ScopedAccess(preset.folders); recount()
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if event.keyCode == 6, event.modifierFlags.contains(.control) { undo(); return nil }; return event
                }
            }
            .onDisappear { countTask?.cancel(); if let monitor { NSEvent.removeMonitor(monitor) }; access = nil }
    }

    private var selectedFoldersPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L("Valda mappar", "Selected folders")).font(.headline)
                Text(L("Dessa mappar ingår i preseten.", "These folders are included in the preset."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            List(selection: $selectedFolders) {
                ForEach(preset.folders) { folder in
                    selectedFolderRow(folder)
                        .tag(folder.id)
                        .onDrag {
                            dragging = folder.id
                            return NSItemProvider(object: folder.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], isTargeted: nil) { _ in moveFolder(dragging, before: folder.id) }
                }
            }
            .overlay {
                if preset.folders.isEmpty {
                    ContentUnavailableView(
                        L("Inga valda mappar", "No selected folders"),
                        systemImage: "folder.badge.questionmark",
                        description: Text(L("Bocka i mappar i filträdet till höger.", "Check folders in the file tree on the right."))
                    )
                }
            }
            .onDrop(of: [.fileURL], isTargeted: nil, perform: dropFolders)

            HStack {
                Button {
                    removeSelectedFolders()
                } label: {
                    Label(L("Ta bort", "Remove"), systemImage: "minus")
                }
                .disabled(selectedFolders.isEmpty)
                Spacer()
                Text("\(preset.folders.count) " + L("valda", "selected"))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .frame(minWidth: 285, idealWidth: 330, maxWidth: 410, maxHeight: .infinity)
    }

    private var folderBrowserPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Mappar på disk", "Folders on disk")).font(.headline)
                    Text(L("Bläddra i hierarkin och bocka i mappar som skall ingå.", "Browse the hierarchy and check folders to include."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { browse() } label: {
                    Label(L("Lägg till plats…", "Add location…"), systemImage: "folder.badge.plus")
                }
            }

            FolderOutlinePicker(
                roots: roots,
                folders: preset.folders,
                onToggle: { path, bookmark in
                    changeFolders(FolderSelection.toggled(path, bookmark: bookmark, in: preset.folders))
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: nil, perform: dropFolders)

        }
        .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectedFolderRow(_ folder: FolderReference) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path))
                    .resizable().scaledToFit().frame(width: 20, height: 20)
                Text(URL(fileURLWithPath: folder.path).lastPathComponent).font(.body.weight(.medium)).lineLimit(1)
                Spacer()
                Button {
                    removeFolder(folder)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L("Ta bort mappen från preseten", "Remove folder from preset"))
            }
            Text(folder.path)
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(folder.path)
            Toggle(L("Inkludera undermappar", "Include subfolders"), isOn: Binding(
                get: { folder.recursive },
                set: { updateRecursive(folder, to: $0) }
            ))
            .toggleStyle(.checkbox).font(.caption)
            if let exclusions = folder.excludedRelativePaths, !exclusions.isEmpty {
                Label(
                    "\(exclusions.count) " + L(exclusions.count == 1 ? "undantagen undermapp" : "undantagna undermappar", exclusions.count == 1 ? "excluded subfolder" : "excluded subfolders"),
                    systemImage: "folder.badge.minus"
                )
                .font(.caption2).foregroundStyle(.secondary)
                .help(exclusions.sorted().joined(separator: "\n"))
            }
        }
        .padding(.vertical, 5)
    }
    func changeFolders(_ folders: [FolderReference]) { guard folders != preset.folders else { return }; history.append(preset.folders); preset.folders = folders; recount() }
    func undo() { guard let previous = history.popLast() else { return }; preset.folders = previous; recount() }
    func updateRecursive(_ folder: FolderReference, to recursive: Bool) {
        var next = preset.folders
        guard let index = next.firstIndex(where: { $0.id == folder.id }) else { return }
        next[index].recursive = recursive
        changeFolders(next)
    }
    func removeFolder(_ folder: FolderReference) {
        changeFolders(FolderSelection.toggled(folder.path, bookmark: folder.bookmark, in: preset.folders))
        selectedFolders.remove(folder.id)
    }
    func removeSelectedFolders() {
        var next = preset.folders
        let removals = preset.folders
            .filter { selectedFolders.contains($0.id) }
            .sorted { URL(fileURLWithPath: $0.path).pathComponents.count > URL(fileURLWithPath: $1.path).pathComponents.count }
        for folder in removals {
            next = FolderSelection.toggled(folder.path, bookmark: folder.bookmark, in: next)
        }
        changeFolders(next)
        selectedFolders.removeAll()
    }
    func moveFolder(_ source: UUID?, before destination: UUID) -> Bool {
        defer { dragging = nil }
        guard let source,
              let from = preset.folders.firstIndex(where: { $0.id == source }),
              let to = preset.folders.firstIndex(where: { $0.id == destination }),
              from != to else { return false }
        var next = preset.folders
        let moving = next.remove(at: from)
        next.insert(moving, at: from < to ? to - 1 : to)
        changeFolders(next)
        return true
    }
    func browse() {
        chooseFolders { folders in
            var next = preset.folders
            for folder in folders {
                addBrowserRoot(folder)
                if !FolderSelection.isIncluded(folder.path, in: next) {
                    next = FolderSelection.toggled(folder.path, bookmark: folder.bookmark, in: next)
                } else if let index = next.firstIndex(where: { $0.path == folder.path }) { next[index].bookmark = folder.bookmark }
            }
            access = ScopedAccess(next)
            changeFolders(next)
        }
    }
    func recount() {
        countTask?.cancel(); counting = true
        let folders = preset.folders, sort = preset.sort
        countTask = Task {
            try? await Task.sleep(for: .milliseconds(200)); guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .utility) { Catalog.scan(folders, sort: sort) }.value
            guard !Task.isCancelled else { return }; countResult = result; counting = false
        }
    }
    func dropFolders(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return }
                let folder = FolderReference(path: url.path, bookmark: try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil))
                Task { @MainActor in
                    addBrowserRoot(folder)
                    access = ScopedAccess(preset.folders + [folder])
                    guard !FolderSelection.isIncluded(folder.path, in: preset.folders) else { return }
                    changeFolders(FolderSelection.toggled(folder.path, bookmark: folder.bookmark, in: preset.folders))
                }
            }
        }; return true
    }

    func addBrowserRoot(_ folder: FolderReference) {
        let path = URL(fileURLWithPath: folder.path).standardizedFileURL.path
        if let ancestor = roots.firstIndex(where: { root in
            let rootPath = URL(fileURLWithPath: root.path).standardizedFileURL.path
            return path == rootPath || path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
        }) {
            if path == URL(fileURLWithPath: roots[ancestor].path).standardizedFileURL.path { roots[ancestor] = folder }
            return
        }
        roots.removeAll { root in
            let rootPath = URL(fileURLWithPath: root.path).standardizedFileURL.path
            return rootPath.hasPrefix(path.hasSuffix("/") ? path : path + "/")
        }
        roots.append(folder)
    }

    func topLevelRoots(_ folders: [FolderReference]) -> [FolderReference] {
        folders.filter { candidate in
            let path = URL(fileURLWithPath: candidate.path).standardizedFileURL.path
            return !folders.contains { other in
                guard other.id != candidate.id else { return false }
                let otherPath = URL(fileURLWithPath: other.path).standardizedFileURL.path
                return path.hasPrefix(otherPath.hasSuffix("/") ? otherPath : otherPath + "/")
            }
        }
    }

    func browserRoots() -> [FolderReference] {
        let keys: [URLResourceKey] = [.volumeIsBrowsableKey, .volumeNameKey]
        let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []
        let urls = mounted.filter {
            (try? $0.resourceValues(forKeys: Set(keys)).volumeIsBrowsable) != false
        }
        let available = urls.isEmpty ? [URL(fileURLWithPath: "/")] : urls
        var seen = Set<String>()
        return available
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
            .sorted { left, right in
                if left.path == "/" { return true }
                if right.path == "/" { return false }
                return FileManager.default.displayName(atPath: left.path)
                    .localizedStandardCompare(FileManager.default.displayName(atPath: right.path)) == .orderedAscending
            }
            .map { FolderReference(path: $0.path) }
    }
}
