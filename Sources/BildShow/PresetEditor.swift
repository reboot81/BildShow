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
    @State private var selectedTree: Set<String> = []
    @State private var selectedFolders: Set<UUID> = []
    @State private var history: [[FolderReference]] = []
    @State private var advanced = false
    @State private var counting = false
    @State private var countResult = ScanResult()
    @State private var countTask: Task<Void, Never>?
    @State private var monitor: Any?
    @State private var dragging: UUID?
    @State private var search = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "rectangle.stack.badge.plus").font(.title2).foregroundStyle(.tint)
                TextField(L("Presetens namn", "Preset name"), text: $preset.name).textFieldStyle(.roundedBorder).font(.title3)
                Button { advanced.toggle() } label: { Label(L("Bildspelsinställningar", "Slideshow settings"), systemImage: "slider.horizontal.3") }
            }.fixedSize(horizontal: false, vertical: true).padding(20)
            if advanced {
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
                    VStack(alignment: .leading, spacing: 0) {
                        Text(L("Inkluderade mappar", "Included folders")).font(.headline).padding()
                        List(selection: $selectedFolders) {
                            ForEach(preset.folders) { folder in
                                VStack(alignment: .leading, spacing: 5) {
                                    Label(URL(fileURLWithPath: folder.path).lastPathComponent, systemImage: "folder.fill").font(.body.weight(.medium))
                                    Text(folder.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(folder.path)
                                    Toggle(L("Inkludera undermappar", "Include subfolders"), isOn: Binding(get: { folder.recursive }, set: { value in
                                        var next = preset.folders; if let i = next.firstIndex(where: { $0.id == folder.id }) { next[i].recursive = value }; changeFolders(next)
                                    })).toggleStyle(.checkbox).font(.caption)
                                }.padding(.vertical, 5).tag(folder.id)
                                    .onDrag { dragging = folder.id; return NSItemProvider(object: folder.id.uuidString as NSString) }
                                    .onDrop(of: [.text], isTargeted: nil) { _ in
                                        guard let source = dragging, let from = preset.folders.firstIndex(where: { $0.id == source }), let to = preset.folders.firstIndex(where: { $0.id == folder.id }), from != to else { return false }
                                        var next = preset.folders; let moving = next.remove(at: from); next.insert(moving, at: to); changeFolders(next); dragging = nil; return true
                                    }
                            }
                        }.overlay { if preset.folders.isEmpty { ContentUnavailableView(L("Lägg till dina bildmappar", "Add your image folders"), systemImage: "folder.badge.plus", description: Text(L("Välj till höger eller dra mappar från Finder.", "Select on the right or drag folders from Finder."))) } }
                            .onDrop(of: [.fileURL], isTargeted: nil, perform: dropFolders)
                    }.frame(minWidth: 290, idealWidth: 420, maxHeight: .infinity)
                    VStack(spacing: 18) {
                        Button { addSelected() } label: { Image(systemName: "chevron.left.2").frame(width: 30, height: 24) }.disabled(selectedTree.isEmpty).help(L("Lägg till markerade mappar", "Add selected folders"))
                        Button { changeFolders(preset.folders.filter { !selectedFolders.contains($0.id) }); selectedFolders = [] } label: { Image(systemName: "chevron.right.2").frame(width: 30, height: 24) }.disabled(selectedFolders.isEmpty).help(L("Ta bort ur preset", "Remove from preset"))
                    }.padding(12).frame(width: 72).frame(maxHeight: .infinity)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(L("Mappar på disk", "Folders on disk")).font(.headline)
                            Spacer()
                            Button { browse() } label: { Label(L("Bläddra…", "Browse…"), systemImage: "folder.badge.plus") }
                        }.padding()
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(roots) { root in FolderTreeRow(url: URL(fileURLWithPath: root.path), selection: $selectedTree, initiallyExpanded: true) }
                            }.padding(.horizontal, 8)
                            if roots.isEmpty {
                                ContentUnavailableView(L("Välj en plats", "Choose a location"), systemImage: "externaldrive", description: Text(L("Bläddra ger BildShow åtkomst till mapparna du väljer.", "Browse grants BildShow access to the folders you select."))).padding(.top, 70)
                            }
                        }
                    }.frame(minWidth: 300, idealWidth: 420, maxHeight: .infinity)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
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
        }.frame(width: 1000, height: 690)
            .onAppear {
                roots = preset.folders; access = ScopedAccess(roots); recount()
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if event.keyCode == 6, event.modifierFlags.contains(.control) { undo(); return nil }; return event
                }
            }
            .onDisappear { countTask?.cancel(); if let monitor { NSEvent.removeMonitor(monitor) }; access = nil }
    }
    func changeFolders(_ folders: [FolderReference]) { guard folders != preset.folders else { return }; history.append(preset.folders); preset.folders = folders; recount() }
    func undo() { guard let previous = history.popLast() else { return }; preset.folders = previous; recount() }
    func browse() {
        chooseFolders { folders in
            for folder in folders {
                if let index = roots.firstIndex(where: { $0.path == folder.path }) { roots[index] = folder }
                else { roots.append(folder) }
                if let index = preset.folders.firstIndex(where: { $0.path == folder.path }) {
                    preset.folders[index].bookmark = folder.bookmark
                }
            }
            access = ScopedAccess(roots); selectedTree = Set(folders.map(\.path))
        }
    }
    func addSelected() {
        var next = preset.folders
        for path in selectedTree.sorted() where !next.contains(where: { $0.path == path }) {
            let url = URL(fileURLWithPath: path)
            next.append(FolderReference(path: path, bookmark: try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)))
        }
        changeFolders(next)
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
                    guard !preset.folders.contains(where: { $0.path == folder.path }) else { return }
                    roots.append(folder); access = ScopedAccess(roots); changeFolders(preset.folders + [folder])
                }
            }
        }; return true
    }
}

struct FolderTreeRow: View {
    let url: URL
    @Binding var selection: Set<String>
    var initiallyExpanded = false
    @State private var expanded = false
    @State private var children: [URL] = []
    @State private var count: Int?
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(children, id: \.path) { child in FolderTreeRow(url: child, selection: $selection).padding(.leading, 5) }
        } label: {
            HStack {
                Image(systemName: "folder.fill").foregroundStyle(.tint)
                Text(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent).lineLimit(1)
                Spacer()
                if let count { Text("\(count)").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
            }.padding(6).background(selection.contains(url.path) ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle()).onTapGesture {
                    if NSEvent.modifierFlags.contains(.command) { if !selection.insert(url.path).inserted { selection.remove(url.path) } }
                    else { selection = [url.path] }
                }.help(url.path)
        }.onChange(of: expanded) { _, value in if value { loadChildren() } }
            .task {
                expanded = initiallyExpanded
                let root = url
                let result = await Task.detached(priority: .utility) { () -> Int in
                    let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
                    var count = 0
                    while let url = enumerator?.nextObject() as? URL {
                        if Catalog.extensions.contains(url.pathExtension.lowercased()), (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { count += 1 }
                    }; return count
                }.value
                if !Task.isCancelled { count = result }
            }
    }
    func loadChildren() {
        let root = url
        Task {
            children = await Task.detached(priority: .utility) {
                ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])) ?? [])
                    .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            }.value
        }
    }
}
