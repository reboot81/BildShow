import AppKit
import SwiftUI
import BildShowCore

func L(_ sv: String, _ en: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("sv") == true ? sv : en
}

extension Setting {
    var title: String {
        switch self {
        case .fullscreen: return L("Fullskärm", "Full screen")
        case .interval: return L("Tid mellan bildbyten (s)", "Time between image changes (s)")
        case .transitionDuration: return L("Övergångens längd (s)", "Transition duration (s)")
        case .transition: return L("Övergång", "Transition")
        case .ending: return L("Efter sista bilden", "After the last image")
        case .random: return L("Slumpad ordning", "Shuffle")
        case .manual: return L("Starta med manuell frammatning", "Start with manual advance")
        case .layout: return L("Bildanpassning", "Image layout")
        case .cropLimit: return L("Max beskärning i smart läge (%)", "Maximum crop in smart mode (%)")
        case .placement: return L("Placering av små bilder", "Small image placement")
        case .cropAnchor: return L("Placering vid beskärning", "Crop anchor")
        case .includeGIF: return L("Inkludera GIF", "Include GIF")
        case .minShort: return L("Minsta kortsida (px, 0 = av)", "Minimum short edge (px, 0 = off)")
        case .minLong: return L("Minsta långsida (px, 0 = av)", "Minimum long edge (px, 0 = off)")
        case .feather: return L("Mjuk bildkant", "Soft image edges")
        case .background: return L("Bakgrund", "Background")
        case .prefetch: return L("Förladda kommande bilder", "Preload upcoming images")
        case .filenameAlways: return L("Visa filnamn", "Show filenames")
        }
    }
    var options: [(String, String)] {
        switch self {
        case .transition: return [("crossfade", L("Mjuk övertoning", "Crossfade")), ("fade", L("Tona via bakgrund", "Fade through background")), ("direct", L("Direkt", "Instant"))]
        case .ending: return [("return", L("Återgå till huvudfönstret", "Return to main window")), ("loop", L("Loopa", "Loop"))]
        case .layout: return layoutOptions
        case .placement, .cropAnchor: return [("center", L("Centrerat", "Center")), ("top", L("Upptill", "Top")), ("bottom", L("Nertill", "Bottom")), ("left", L("Till vänster", "Left")), ("right", L("Till höger", "Right"))]
        case .background: return [("black", L("Svart", "Black")), ("gray", L("Mörkgrå", "Dark gray")), ("white", L("Vit", "White"))]
        default: return []
        }
    }
    var range: ClosedRange<Double> {
        switch self {
        case .interval: return 0.25...3600
        case .transitionDuration: return 0...10
        case .cropLimit: return 0...90
        case .prefetch: return 1...8
        default: return 0...100000
        }
    }
}

var layoutOptions: [(String, String)] {
    [("smart", L("Smart anpassning", "Smart fit")), ("fit", L("Visa hela bilden", "Fit entire image")), ("fill", L("Fyll skärmen", "Fill screen")), ("width", L("Anpassa till bredd", "Fit width")), ("height", L("Anpassa till höjd", "Fit height"))]
}

extension PlayerAction {
    var title: String {
        switch self {
        case .pause: return L("Pausa / fortsätt", "Pause / resume")
        case .next: return L("Nästa bild", "Next image")
        case .previous: return L("Föregående bild", "Previous image")
        case .slower: return L("Öka bildtiden", "Increase interval")
        case .faster: return L("Minska bildtiden", "Decrease interval")
        case .mark: return L("Markera för städning", "Mark for cleanup")
        case .undo: return L("Ångra markering", "Undo mark")
        case .filename: return L("Bildtext: filnamn / sökväg / dold", "Caption: filename / path / hidden")
        case .filenames: return L("Filnamn på / av", "Toggle filenames")
        case .fullscreen: return L("Fullskärm på / av", "Toggle full screen")
        case .original: return L("Originalstorlek / anpassa", "Actual size / fit")
        case .zoomIn: return L("Zooma in", "Zoom in")
        case .zoomOut: return L("Zooma ut", "Zoom out")
        case .reveal: return L("Visa i Finder", "Reveal in Finder")
        case .exit: return L("Avsluta bildspel", "End slideshow")
        }
    }
}

final class ScopedAccess {
    let urls: [URL]
    private let active: [URL]
    init(_ folders: [FolderReference]) {
        var urls: [URL] = [], active: [URL] = []
        for folder in folders {
            var stale = false
            let url = folder.bookmark.flatMap { try? URL(resolvingBookmarkData: $0, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) } ?? URL(fileURLWithPath: folder.path)
            urls.append(url)
            if url.startAccessingSecurityScopedResource() { active.append(url) }
        }
        self.urls = urls; self.active = active
    }
    deinit { active.forEach { $0.stopAccessingSecurityScopedResource() } }
}

func chooseFolders(completion: @escaping ([FolderReference]) -> Void) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
    panel.prompt = L("Lägg till mappar", "Add folders")
    panel.begin { response in
        guard response == .OK else { return }
        completion(panel.urls.map {
            FolderReference(path: $0.path, bookmark: try? $0.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil))
        })
    }
}

func showError(_ message: String) {
    let alert = NSAlert(); alert.messageText = "BildShow"; alert.informativeText = message
    alert.runModal()
}
