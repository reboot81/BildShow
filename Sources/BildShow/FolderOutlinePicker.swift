import AppKit
import SwiftUI
import BildShowCore

private final class FolderTreeNode: @unchecked Sendable {
    let url: URL
    let bookmark: Data?
    let isVolumeRoot: Bool
    let displayName: String
    var children: [FolderTreeNode]?
    var isLoading = false
    var candidateCount: Int?
    var isCounting = false
    let modified: Date?

    init(url: URL, bookmark: Data?, isVolumeRoot: Bool = false) {
        self.url = url
        self.bookmark = bookmark
        self.isVolumeRoot = isVolumeRoot
        self.displayName = FileManager.default.displayName(atPath: url.path)
        self.modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

struct FolderOutlinePicker: NSViewRepresentable {
    var roots: [FolderReference]
    var folders: [FolderReference]
    var revealPath: String?
    var onToggle: (String, Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView()
        outline.usesAlternatingRowBackgroundColors = true
        outline.rowHeight = 29
        outline.indentationPerLevel = 18
        outline.allowsEmptySelection = true
        outline.allowsMultipleSelection = false
        outline.autosaveExpandedItems = false
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        let menu = NSMenu()
        let reveal = NSMenuItem(title: L("Visa i Finder", "Show in Finder"), action: #selector(Coordinator.revealInFinder(_:)), keyEquivalent: "")
        reveal.target = context.coordinator
        let copy = NSMenuItem(title: L("Kopiera sökväg", "Copy Path"), action: #selector(Coordinator.copyPath(_:)), keyEquivalent: "")
        copy.target = context.coordinator
        menu.items = [reveal, copy]
        outline.menu = menu

        let name = NSTableColumn(identifier: .name)
        name.title = L("Namn", "Name")
        name.minWidth = 300
        name.width = 470
        outline.addTableColumn(name)
        outline.outlineTableColumn = name

        let images = NSTableColumn(identifier: .images)
        images.title = L("Bilder", "Images")
        images.minWidth = 65
        images.maxWidth = 90
        images.width = 75
        outline.addTableColumn(images)

        let modified = NSTableColumn(identifier: .modified)
        modified.title = L("Ändrad", "Date Modified")
        modified.minWidth = 150
        modified.width = 190
        outline.addTableColumn(modified)

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        context.coordinator.outline = outline
        context.coordinator.rebuildRoots(from: roots)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateRootsIfNeeded(roots)
        context.coordinator.outline?.reloadData()
        context.coordinator.revealIfNeeded(revealPath)
    }

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: FolderOutlinePicker
        weak var outline: NSOutlineView?
        private var rootNodes: [FolderTreeNode] = []
        private var rootSignature: [String] = []
        private var lastRevealPath: String?
        private let counter = OperationQueue()
        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = .autoupdatingCurrent
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter
        }()

        init(_ parent: FolderOutlinePicker) {
            self.parent = parent
            counter.maxConcurrentOperationCount = 2
            counter.qualityOfService = .utility
        }

        func rebuildRoots(from references: [FolderReference]) {
            lastRevealPath = nil
            rootSignature = references.map { $0.id.uuidString + "|" + $0.path }
            rootNodes = references.map { reference in
                var stale = false
                let resolved = reference.bookmark.flatMap {
                    try? URL(resolvingBookmarkData: $0, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
                } ?? URL(fileURLWithPath: reference.path)
                return FolderTreeNode(url: resolved, bookmark: reference.bookmark, isVolumeRoot: true)
            }
            outline?.reloadData()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.rootNodes.forEach { self.outline?.expandItem($0) }
                self.revealIfNeeded(self.parent.revealPath)
            }
        }

        func updateRootsIfNeeded(_ references: [FolderReference]) {
            let signature = references.map { $0.id.uuidString + "|" + $0.path }
            if signature != rootSignature { rebuildRoots(from: references) }
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let node = item as? FolderTreeNode else { return rootNodes.count }
            return node.children?.count ?? 0
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let node = item as? FolderTreeNode else { return rootNodes[index] }
            return node.children![index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { true }

        func outlineViewItemWillExpand(_ notification: Notification) {
            guard let node = notification.userInfo?["NSObject"] as? FolderTreeNode else { return }
            loadChildren(of: node)
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? FolderTreeNode, let identifier = tableColumn?.identifier else { return nil }
            switch identifier {
            case .name:
                let cell = (outlineView.makeView(withIdentifier: .nameCell, owner: self) as? FolderNameCell) ?? FolderNameCell()
                cell.identifier = .nameCell
                cell.checkbox.state = FolderSelection.isIncluded(node.url.path, in: parent.folders) ? .on : .off
                cell.checkbox.node = node
                cell.checkbox.target = self
                cell.checkbox.action = #selector(toggleFolder(_:))
                cell.checkbox.toolTip = L("Ta med eller uteslut mappen", "Include or exclude this folder")
                cell.icon.image = NSWorkspace.shared.icon(forFile: node.url.path)
                cell.name.stringValue = node.displayName
                cell.name.toolTip = node.url.path
                return cell
            case .images:
                let cell = textCell(in: outlineView, identifier: .imagesCell)
                cell.textField?.alignment = .right
                cell.textField?.stringValue = node.isVolumeRoot ? "—" : node.candidateCount.map(String.init) ?? "…"
                if !node.isVolumeRoot { startCounting(node) }
                return cell
            default:
                let cell = textCell(in: outlineView, identifier: .modifiedCell)
                cell.textField?.stringValue = node.modified.map(Self.dateFormatter.string(from:)) ?? "—"
                return cell
            }
        }

        @objc func revealInFinder(_ sender: Any?) {
            guard let node = contextNode() else { return }
            NSWorkspace.shared.activateFileViewerSelecting([node.url])
        }

        @objc func copyPath(_ sender: Any?) {
            guard let node = contextNode() else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.url.path, forType: .string)
        }

        private func contextNode() -> FolderTreeNode? {
            guard let outline, outline.clickedRow >= 0 else { return nil }
            return outline.item(atRow: outline.clickedRow) as? FolderTreeNode
        }

        func revealIfNeeded(_ path: String?) {
            guard let path else { return }
            let target = URL(fileURLWithPath: path).standardizedFileURL.path
            guard target != lastRevealPath else { return }
            lastRevealPath = target
            guard let root = rootNodes
                .filter({ contains(target, in: $0.url.standardizedFileURL.path) })
                .max(by: { $0.url.path.count < $1.url.path.count }) else { return }
            reveal(target, from: root)
        }

        private func reveal(_ target: String, from node: FolderTreeNode) {
            outline?.expandItem(node)
            if node.url.standardizedFileURL.path == target {
                selectAndScroll(node)
                return
            }
            loadChildren(of: node) { [weak self, weak node] in
                guard let self, let node,
                      let child = node.children?.first(where: { self.contains(target, in: $0.url.standardizedFileURL.path) }) else { return }
                self.reveal(target, from: child)
            }
        }

        private func selectAndScroll(_ node: FolderTreeNode) {
            guard let outline else { return }
            let row = outline.row(forItem: node)
            guard row >= 0 else { return }
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outline.scrollRowToVisible(row)
        }

        private func contains(_ target: String, in folder: String) -> Bool {
            target == folder || target.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
        }

        @objc private func toggleFolder(_ sender: NSButton) {
            guard let node = (sender as? FolderNodeButton)?.node else { return }
            let bookmark = (try? node.url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)) ?? node.bookmark
            parent.onToggle(node.url.path, bookmark)
        }

        private func loadChildren(of node: FolderTreeNode, completion: (() -> Void)? = nil) {
            if node.children != nil { completion?(); return }
            guard !node.isLoading else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak node] in
                    guard let self, let node else { return }
                    self.loadChildren(of: node, completion: completion)
                }
                return
            }
            node.isLoading = true
            let url = node.url
            let bookmark = node.bookmark
            DispatchQueue.global(qos: .userInitiated).async { [weak self, weak node] in
                let urls = ((try? FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )) ?? []).filter {
                    guard let values = try? $0.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) else { return false }
                    return values.isDirectory == true && values.isPackage != true
                }.sorted {
                    FileManager.default.displayName(atPath: $0.path)
                        .localizedStandardCompare(FileManager.default.displayName(atPath: $1.path)) == .orderedAscending
                }
                let children = urls.map { FolderTreeNode(url: $0, bookmark: bookmark) }
                DispatchQueue.main.async {
                    guard let self, let node else { return }
                    node.children = children
                    node.isLoading = false
                    self.outline?.reloadItem(node, reloadChildren: true)
                    self.outline?.expandItem(node)
                    completion?()
                }
            }
        }

        private func startCounting(_ node: FolderTreeNode) {
            guard node.candidateCount == nil, !node.isCounting else { return }
            node.isCounting = true
            let url = node.url
            counter.addOperation { [weak self, weak node] in
                let files = (try? FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )) ?? []
                let count = files.filter {
                    Catalog.extensions.contains($0.pathExtension.lowercased()) &&
                    (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                }.count
                DispatchQueue.main.async {
                    guard let self, let node else { return }
                    node.candidateCount = count
                    node.isCounting = false
                    self.outline?.reloadItem(node)
                }
            }
        }

        private func textCell(in outlineView: NSOutlineView, identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            if let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView { return cell }
            let cell = NSTableCellView()
            cell.identifier = identifier
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            label.textColor = .secondaryLabelColor
            cell.textField = label
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }
    }
}

private final class FolderNodeButton: NSButton {
    var node: FolderTreeNode?
}

private final class FolderNameCell: NSTableCellView {
    let checkbox: FolderNodeButton = {
        let button = FolderNodeButton()
        button.setButtonType(.switch)
        button.title = ""
        return button
    }()
    let icon = NSImageView()
    let name = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        checkbox.setButtonType(.switch)
        checkbox.allowsMixedState = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        name.translatesAutoresizingMaskIntoConstraints = false
        name.lineBreakMode = .byTruncatingMiddle
        addSubview(checkbox); addSubview(icon); addSubview(name)
        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkbox.widthAnchor.constraint(equalToConstant: 18),
            checkbox.heightAnchor.constraint(equalToConstant: 18),
            icon.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 3),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 19),
            icon.heightAnchor.constraint(equalToConstant: 19),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
            name.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            name.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private extension NSUserInterfaceItemIdentifier {
    static let name = Self("name")
    static let images = Self("images")
    static let modified = Self("modified")
    static let nameCell = Self("nameCell")
    static let imagesCell = Self("imagesCell")
    static let modifiedCell = Self("modifiedCell")
}
