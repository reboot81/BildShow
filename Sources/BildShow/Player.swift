import AppKit
import IOKit.pwr_mgt
import BildShowCore

private enum CaptionMode {
    case hidden, filename, fullPath

    var next: CaptionMode {
        switch self {
        case .hidden: return .filename
        case .filename: return .fullPath
        case .fullPath: return .hidden
        }
    }
}

final class PlaybackWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor final class PlayerCoordinator: NSObject, ObservableObject, NSWindowDelegate {
    @Published var isPlaying = false
    @Published var starting = false
    let store: AppStore
    private var window: PlaybackWindow?
    private weak var origin: NSWindow?
    private var surface: PlayerSurface?
    private var renderer: MetalRenderer?
    private var access: ScopedAccess?
    private var preset: Preset?
    private var settings = Preferences()
    private var images: [String: ImageItem] = [:]
    private var order: [String] = []
    private var index = -1
    private var failed = Set<String>()
    private var paused = false
    private var captionMode: CaptionMode = .hidden
    private var timer: Timer?
    private var animation: Task<Void, Never>?
    private var request: Task<Void, Never>?
    private var requestID = UUID()
    private var preloads: [Task<Void, Never>] = []
    private var undoMarks: [String] = []
    private var overrideScale: Double?
    private var assertion: IOPMAssertionID = 0
    private var oldPresentation: NSApplication.PresentationOptions = []
    private var fullscreen = true
    private var demoMode = false
    private var startID = UUID()
    private var renderID = UUID()
    private var refreshTask: Task<Void, Never>?
    private var pendingImages: [ImageItem]?
    init(store: AppStore) { self.store = store; super.init() }
    private var current: ImageItem? { order.indices.contains(index) ? images[order[index]] : nil }
    private var displaySize: CGSize {
        guard let window, let surface else { return CGSize(width: 3840, height: 2160) }
        let scale = window.backingScaleFactor
        return CGSize(width: max(1, surface.bounds.width * scale), height: max(1, surface.bounds.height * scale))
    }
    func start(_ preset: Preset, restart: Bool = false) {
        guard !starting else { return }
        stop(); starting = true; demoMode = false; origin = NSApp.keyWindow
        let startToken = UUID(); startID = startToken
        self.preset = preset; settings = store.preferences.resolved(for: preset)
        access = ScopedAccess(preset.folders)
        Task { [weak self] in
            guard let self else { return }
            let existing = store.indexes[preset.id]
            let result: ScanResult
            if let existing { result = existing } else { result = await store.refresh(preset) }
            guard starting, startID == startToken else { return }
            let selected = result.images.filter { $0.included(in: self.settings) && !preset.markedPaths.contains($0.path) }
            guard !selected.isEmpty else {
                starting = false; access = nil
                showError(L("Inga tillgängliga bilder matchar presetens inställningar. Kontrollera mappar och filter.", "No available images match this preset. Check its folders and filters.")); return
            }
            images = Dictionary(selected.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
            order = PlaybackOrder.reconcile(saved: restart ? [] : store.order(for: preset.id), available: selected.map(\.path), random: settings[.random].bool)
            index = restart ? -1 : ((preset.lastPath.flatMap { self.order.firstIndex(of: $0) } ?? 0) - 1)
            store.saveSequence(order, id: preset.id)
            openWindow(displayID: preset.displayID)
            if existing != nil {
                refreshTask = Task { [weak self] in
                    guard let self else { return }
                    let refreshed = await store.refresh(preset)
                    guard !Task.isCancelled, isPlaying else { return }
                    pendingImages = refreshed.images
                }
            }
        }
    }
    func demo(_ preferences: Preferences) {
        stop(); demoMode = true; settings = preferences; settings.values[Setting.ending.rawValue] = .text("loop")
        settings.values[Setting.manual.rawValue] = .bool(false)
        origin = NSApp.keyWindow; starting = true
        guard let source = Bundle.module.url(forResource: "DemoPortrait", withExtension: "png", subdirectory: "Resources") else { starting = false; return }
        let startToken = UUID(); startID = startToken
        Task {
            let result = await Task.detached { DemoImages.prepare(source: source) }.value
            guard starting, startID == startToken else { return }
            guard !result.isEmpty else { starting = false; return }
            images = Dictionary(uniqueKeysWithValues: result.map { ($0.path, $0) })
            order = result.map(\.path); index = -1
            openWindow(displayID: nil)
        }
    }

    private func openWindow(displayID: UInt32?) {
        do { renderer = try MetalRenderer() } catch { starting = false; showError(error.localizedDescription); return }
        let screen = NSScreen.screens.first { ( $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID } ?? origin?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        fullscreen = settings[.fullscreen].bool
        let frame = fullscreen ? screen.frame : CGRect(x: screen.visibleFrame.midX - 600, y: screen.visibleFrame.midY - 375, width: 1200, height: 750)
        let window = PlaybackWindow(contentRect: frame, styleMask: fullscreen ? [.borderless] : [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false, screen: screen)
        window.title = preset?.name ?? L("BildShow – Demo", "BildShow – Demo")
        window.delegate = self; window.isReleasedWhenClosed = false; window.backgroundColor = .black; window.acceptsMouseMovedEvents = true
        window.isOpaque = true; window.hasShadow = !fullscreen
        window.collectionBehavior = [.fullScreenPrimary]
        let surface = PlayerSurface(frame: CGRect(origin: .zero, size: frame.size), renderer: renderer!, action: { [weak self] in self?.perform($0) }, keyboard: { [weak self] in self?.key($0) }, mouse: { [weak self] in self?.mouse($0) })
        surface.autoresizingMask = [.width, .height]
        self.window = window; self.surface = surface; window.contentView = surface
        oldPresentation = NSApp.presentationOptions
        if fullscreen { NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar] }
        window.setFrame(frame, display: false)
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(surface)
        window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        starting = false; isPlaying = true; paused = settings[.manual].bool; failed = []; undoMarks = []
        captionMode = settings[.filenameAlways].bool ? .filename : .hidden
        overrideScale = nil
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "BildShow slideshow" as CFString, &assertion)
        surface.message(L("Förbereder bilder…", "Preparing images…"), duration: 10)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, self.isPlaying, self.window === window else { return }
            self.advance(1, manual: true)
        }
    }
    func perform(_ action: PlayerAction) {
        switch action {
        case .pause:
            paused.toggle(); if paused { timer?.invalidate() } else { schedule() }
            surface?.message(paused ? L("Pausad", "Paused") : L("Spelar", "Playing"))
        case .next: advance(1, manual: true)
        case .previous: advance(-1, manual: true)
        case .slower, .faster:
            let interval = min(3600, max(0.25, settings[.interval].number + (action == .slower ? 1 : -1)))
            settings.values[Setting.interval.rawValue] = .number(interval)
            if let id = preset?.id, !demoMode { store.update(id) { $0.overrides[Setting.interval.rawValue] = .number(interval) } }
            schedule(); surface?.message(String(format: "%.2g s", interval))
        case .mark:
            guard let current, let id = preset?.id, !demoMode else { return }
            undoMarks.append(current.path); preset?.markedPaths.insert(current.path)
            store.update(id) { $0.markedPaths.insert(current.path) }
            surface?.message(L("Markerad för städning · ångra med ", "Marked for cleanup · undo with ") + (settings.shortcuts[PlayerAction.undo.rawValue] ?? PlayerAction.undo.initial).label)
            advance(1, manual: true)
        case .undo:
            guard let path = undoMarks.popLast(), let id = preset?.id else { return }
            preset?.markedPaths.remove(path); store.update(id) { $0.markedPaths.remove(path) }; surface?.message(L("Markeringen ångrad", "Mark undone"))
        case .filename: captionMode = captionMode.next; updateCaption()
        case .filenames:
            settings.values[Setting.filenameAlways.rawValue] = .bool(!settings[.filenameAlways].bool)
            captionMode = settings[.filenameAlways].bool ? .filename : .hidden
            if let id = preset?.id, !demoMode { store.update(id) { $0.overrides[Setting.filenameAlways.rawValue] = settings[.filenameAlways] } }; updateCaption()
        case .fullscreen: toggleFullscreen()
        case .original:
            overrideScale = overrideScale == nil ? 1 : nil; rerender()
        case .zoomIn: overrideScale = min(8, (overrideScale ?? currentScale()) * 1.25); rerender()
        case .zoomOut: overrideScale = max(0.05, (overrideScale ?? currentScale()) / 1.25); rerender()
        case .reveal: if let current { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: current.path)]) }
        case .exit: stop()
        }
    }
    private func currentScale() -> Double {
        guard let current else { return 1 }
        return ImageLayout.calculate(width: Double(current.width), height: Double(current.height), screenWidth: displaySize.width, screenHeight: displaySize.height, settings: settings).scale
    }
    private func key(_ event: NSEvent) {
        if event.keyCode == 53 { stop(); return }
        let flags = event.modifierFlags.intersection([.command, .shift, .control, .option]).rawValue
        if let action = PlayerAction.allCases.first(where: { action in
            let binding = settings.shortcuts[action.rawValue] ?? action.initial
            return binding.code == event.keyCode && binding.modifiers == flags
        }) { if !event.isARepeat || [.slower, .faster, .next, .previous, .zoomIn, .zoomOut].contains(action) { perform(action) } }
    }
    private func mouse(_ key: String) {
        let mapping = settings.mouse[key] ?? "none"
        if mapping == "menu" { surface?.showMenu(paused: paused) }
        else if let action = PlayerAction(rawValue: mapping) { perform(action) }
    }
    private func advance(_ direction: Int, manual: Bool) {
        timer?.invalidate(); animation?.cancel(); request?.cancel(); overrideScale = nil
        let token = UUID(); requestID = token
        request = Task { [weak self] in
            guard let self else { return }
            var candidate = index + direction
            var attempted = Set<String>()
            while isPlaying && !Task.isCancelled {
                if candidate < 0 { candidate = 0 }
                if candidate >= order.count {
                    if settings[.ending].text != "loop" { stop(); return }
                    let previousPath = current?.path
                    if let pendingImages {
                        let filtered = pendingImages.filter { $0.included(in: self.settings) }
                        images = Dictionary(filtered.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
                        order = filtered.map(\.path); self.pendingImages = nil
                    }
                    order = PlaybackOrder.nextRound(order.filter { !self.failed.contains($0) && !(self.preset?.markedPaths.contains($0) ?? false) }, random: settings[.random].bool, previous: previousPath)
                    if let id = preset?.id, !demoMode { store.saveSequence(order, id: id) }
                    candidate = 0
                }
                guard order.indices.contains(candidate) else { stop(); return }
                let path = order[candidate]
                if !attempted.insert(path).inserted { stop(); return }
                if failed.contains(path) || (preset?.markedPaths.contains(path) ?? false) || images[path] == nil {
                    if direction < 0 && candidate == 0 { schedule(); return }
                    candidate += direction; continue
                }
                let item = images[path]!
                do {
                    let frame = try await ImagePipeline.shared.load(item, settings: settings, size: displaySize)
                    guard requestID == token, !Task.isCancelled, isPlaying else { return }
                    index = candidate
                    let transition = manual || settings[.transition].text == "direct" ? 0 : min(settings[.transitionDuration].number, settings[.interval].number / 2)
                    renderer?.show(frame, duration: transition, mode: settings[.transition].text, background: settings[.background].text)
                    if let id = preset?.id, !demoMode { store.update(id) { $0.lastPath = path } }
                    updateCaption(); surface?.finishLoading()
                    prefetch(); schedule(); startAnimation(item, first: frame, after: transition, token: token)
                    return
                } catch {
                    guard requestID == token, !Task.isCancelled else { return }
                    failed.insert(path); store.log("\(URL(fileURLWithPath: path).lastPathComponent): \(error.localizedDescription)")
                    if direction < 0 && candidate == 0 { schedule(); return }
                    candidate += direction
                }
            }
        }
    }
    private func schedule() {
        timer?.invalidate(); guard isPlaying, !paused else { return }
        timer = Timer.scheduledTimer(withTimeInterval: max(0.25, settings[.interval].number), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.advance(1, manual: false) }
        }
    }
    private func prefetch() {
        preloads.forEach { $0.cancel() }; preloads.removeAll()
        let amount = Int(settings[.prefetch].number)
        var targets = Array((index + 1)..<min(order.count, index + 1 + amount))
        if index > 0 { targets.append(index - 1) }
        if settings[.ending].text == "loop" && targets.count < amount { targets += Array(0..<min(order.count, amount - targets.count)) }
        let size = displaySize, preferences = settings
        for position in targets {
            guard let item = images[order[position]], !failed.contains(item.path), !(preset?.markedPaths.contains(item.path) ?? false) else { continue }
            preloads.append(Task { _ = try? await ImagePipeline.shared.load(item, settings: preferences, size: size) })
        }
    }
    private func startAnimation(_ item: ImageItem, first: PreparedFrame, after transition: Double, token: UUID) {
        guard first.frameCount > 1 else { return }
        animation = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(max(transition, first.frameDelay)))
            var next = 1
            while !Task.isCancelled && isPlaying && token == requestID {
                do {
                    let frame = try await ImagePipeline.shared.load(item, settings: settings, size: displaySize, frame: next, overrideScale: overrideScale)
                    guard !Task.isCancelled, token == requestID else { return }
                    renderer?.show(frame, duration: 0, mode: "direct", background: settings[.background].text)
                    try await Task.sleep(for: .seconds(frame.frameDelay)); next = (next + 1) % first.frameCount
                } catch { store.log(error.localizedDescription); return }
            }
        }
    }
    private func updateCaption() {
        guard let current else { surface?.setCaption(""); return }
        switch captionMode {
        case .hidden: surface?.setCaption("")
        case .filename: surface?.setCaption(URL(fileURLWithPath: current.path).lastPathComponent)
        case .fullPath: surface?.setCaption(current.path)
        }
    }
    private func rerender() {
        guard let current else { return }
        animation?.cancel()
        let token = requestID, renderToken = UUID(); renderID = renderToken
        Task {
            if let frame = try? await ImagePipeline.shared.load(current, settings: settings, size: displaySize, overrideScale: overrideScale), token == requestID, renderID == renderToken, isPlaying {
                renderer?.show(frame, duration: 0, mode: "direct", background: settings[.background].text)
            }
        }
    }
    private func toggleFullscreen() {
        guard let window, let screen = window.screen else { return }
        fullscreen.toggle()
        window.styleMask = fullscreen ? [.borderless] : [.titled, .closable, .resizable, .miniaturizable]
        window.hasShadow = !fullscreen
        NSApp.presentationOptions = fullscreen ? [.autoHideDock, .autoHideMenuBar] : oldPresentation
        window.setFrame(fullscreen ? screen.frame : CGRect(x: screen.visibleFrame.midX - 600, y: screen.visibleFrame.midY - 375, width: 1200, height: 750), display: true)
        window.makeFirstResponder(surface); rerender()
    }
    func windowDidResize(_ notification: Notification) { if isPlaying { rerender() } }
    func windowDidChangeScreen(_ notification: Notification) { if isPlaying { rerenderAfterDisplayChange() } }
    func windowDidChangeBackingProperties(_ notification: Notification) { if isPlaying { rerenderAfterDisplayChange() } }
    private func rerenderAfterDisplayChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isPlaying else { return }
            self.window?.contentView?.layoutSubtreeIfNeeded()
            self.rerender()
        }
    }
    func windowWillClose(_ notification: Notification) { stop(closeWindow: false) }
    func stop(closeWindow: Bool = true) {
        let wasPlaying = isPlaying
        isPlaying = false; starting = false; requestID = UUID(); startID = UUID(); renderID = UUID()
        timer?.invalidate(); timer = nil; request?.cancel(); request = nil; animation?.cancel(); animation = nil
        preloads.forEach { $0.cancel() }; preloads.removeAll(); refreshTask?.cancel(); refreshTask = nil
        if closeWindow { window?.delegate = nil; window?.close() }
        window = nil; surface = nil; renderer = nil; access = nil; pendingImages = nil
        if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }
        if wasPlaying { NSApp.presentationOptions = oldPresentation; origin?.makeKeyAndOrderFront(nil) }
        preset = nil; images = [:]; order = []; index = -1
    }
}

final class PlayerSurface: NSView {
    private let action: (PlayerAction) -> Void
    private let keyboard: (NSEvent) -> Void
    private let mouse: (String) -> Void
    private let caption = NSTextField(labelWithString: "")
    private let hud = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?
    private var mouseTimer: Timer?
    private var lastScroll = 0.0
    private var loading = true
    override var acceptsFirstResponder: Bool { true }
    init(frame: CGRect, renderer: MetalRenderer, action: @escaping (PlayerAction) -> Void, keyboard: @escaping (NSEvent) -> Void, mouse: @escaping (String) -> Void) {
        self.action = action; self.keyboard = keyboard; self.mouse = mouse
        super.init(frame: frame)
        renderer.view.translatesAutoresizingMaskIntoConstraints = false; addSubview(renderer.view)
        NSLayoutConstraint.activate([renderer.view.leadingAnchor.constraint(equalTo: leadingAnchor), renderer.view.trailingAnchor.constraint(equalTo: trailingAnchor), renderer.view.topAnchor.constraint(equalTo: topAnchor), renderer.view.bottomAnchor.constraint(equalTo: bottomAnchor)])
        for label in [caption, hud] {
            label.translatesAutoresizingMaskIntoConstraints = false; label.textColor = .white; label.font = .systemFont(ofSize: 15, weight: .medium)
            label.alignment = .center; label.lineBreakMode = .byTruncatingMiddle
            label.wantsLayer = true; label.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor; label.layer?.cornerRadius = 6
            label.isHidden = true; addSubview(label)
        }
        NSLayoutConstraint.activate([caption.centerXAnchor.constraint(equalTo: centerXAnchor), caption.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20), caption.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.9), caption.heightAnchor.constraint(equalToConstant: 30),
            hud.centerXAnchor.constraint(equalTo: centerXAnchor), hud.topAnchor.constraint(equalTo: topAnchor, constant: 30), hud.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.9), hud.heightAnchor.constraint(equalToConstant: 32)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func keyDown(with event: NSEvent) { keyboard(event) }
    override func mouseDown(with event: NSEvent) { mouse("left") }
    override func rightMouseDown(with event: NSEvent) { mouse("right") }
    override func otherMouseDown(with event: NSEvent) { mouse("middle") }
    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > 0.1, CACurrentMediaTime() - lastScroll > 0.25 else { return }
        lastScroll = CACurrentMediaTime(); mouse(event.scrollingDeltaY > 0 ? "scrollUp" : "scrollDown")
    }
    override func mouseMoved(with event: NSEvent) {
        mouseTimer?.invalidate(); mouseTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            if self?.window?.isKeyWindow == true { NSCursor.setHiddenUntilMouseMoves(true) }
        }
    }
    func setCaption(_ text: String) { caption.stringValue = "  " + text + "  "; caption.isHidden = text.isEmpty }
    func message(_ text: String, duration: Double = 1.8) {
        hideWork?.cancel(); hud.stringValue = "  " + text + "  "; hud.isHidden = false
        let work = DispatchWorkItem { [weak self] in self?.hud.isHidden = true }; hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
    func finishLoading() { if loading { hud.isHidden = true; loading = false }; NSCursor.setHiddenUntilMouseMoves(true) }
    func showMenu(paused: Bool) {
        let menu = NSMenu()
        for action in PlayerAction.allCases {
            let item = NSMenuItem(title: action.title, action: #selector(menuAction(_:)), keyEquivalent: "")
            item.representedObject = action.rawValue; item.target = self; menu.addItem(item)
        }
        if let event = NSApp.currentEvent { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
    @objc private func menuAction(_ sender: NSMenuItem) { if let value = sender.representedObject as? String, let action = PlayerAction(rawValue: value) { self.action(action) } }
    deinit { mouseTimer?.invalidate(); hideWork?.cancel() }
}
