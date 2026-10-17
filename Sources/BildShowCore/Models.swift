import Foundation

public enum SettingValue: Codable, Equatable, Sendable {
    case bool(Bool), number(Double), text(String)
    public var bool: Bool { if case .bool(let value) = self { return value }; return false }
    public var number: Double { if case .number(let value) = self { return value }; return 0 }
    public var text: String { if case .text(let value) = self { return value }; return "" }
}

public enum Setting: String, CaseIterable, Codable, Sendable {
    case fullscreen, interval, transitionDuration, transition, ending, random, manual
    case layout, cropLimit, placement, cropAnchor, includeGIF, minShort, minLong
    case feather, background, prefetch, filenameAlways
    public var initial: SettingValue {
        switch self {
        case .fullscreen, .random, .feather: return .bool(true)
        case .manual, .includeGIF, .filenameAlways: return .bool(false)
        case .interval: return .number(2.5)
        case .transitionDuration: return .number(0.5)
        case .transition: return .text("crossfade")
        case .ending: return .text("return")
        case .layout: return .text("smart")
        case .cropLimit: return .number(15)
        case .placement, .cropAnchor: return .text("center")
        case .minShort, .minLong: return .number(0)
        case .background: return .text("black")
        case .prefetch: return .number(3)
        }
    }
}

public struct SizeRule: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var upperScale: Double
    public var maxScale: Double
    public var method: String
    public var sharpening: Double
    public var featherPercent: Double
    public init(id: String, upperScale: Double, maxScale: Double, method: String, sharpening: Double, featherPercent: Double) {
        self.id = id; self.upperScale = upperScale; self.maxScale = maxScale
        self.method = method; self.sharpening = sharpening; self.featherPercent = featherPercent
    }
    public static let defaults: [SizeRule] = [
        .init(id: "reduce", upperScale: 1, maxScale: 1, method: "lanczos", sharpening: 0, featherPercent: 2),
        .init(id: "near", upperScale: 1.25, maxScale: 1.25, method: "bicubic", sharpening: 0, featherPercent: 2),
        .init(id: "medium", upperScale: 2, maxScale: 2, method: "bicubic", sharpening: 0.12, featherPercent: 1),
        .init(id: "small", upperScale: 100000, maxScale: 3, method: "lanczos", sharpening: 0.2, featherPercent: 0.5)
    ]
}

public struct Preferences: Codable, Equatable, Sendable {
    public var values: [String: SettingValue] = [:]
    public var rules: [SizeRule] = SizeRule.defaults
    public var portraitLayout = "inherit"
    public var landscapeLayout = "inherit"
    public var shortcuts: [String: KeyBinding] = [:]
    public var mouse: [String: String] = ["left": "next", "right": "menu", "middle": "pause", "scrollUp": "previous", "scrollDown": "next"]
    public var autostartPreset: UUID?
    public init() {}
    public subscript(_ key: Setting) -> SettingValue {
        guard let value = values[key.rawValue] else { return key.initial }
        switch (key.initial, value) {
        case (.bool, .bool), (.text, .text): return value
        case (.number, .number(let number)):
            guard number.isFinite else { return key.initial }
            let range: ClosedRange<Double>
            switch key {
            case .interval: range = 0.25...3600
            case .transitionDuration: range = 0...30
            case .prefetch: range = 1...8
            case .cropLimit: range = 0...75
            default: range = 0...100000
            }
            return .number(min(range.upperBound, max(range.lowerBound, number)))
        default: return key.initial
        }
    }
    public func resolved(for preset: Preset) -> Preferences {
        var result = self
        result.values.merge(preset.overrides) { _, specific in specific }
        if let rules = preset.rules { result.rules = rules }
        if let layout = preset.portraitLayout { result.portraitLayout = layout }
        if let layout = preset.landscapeLayout { result.landscapeLayout = layout }
        return result
    }
}

public struct FolderReference: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var path: String
    public var bookmark: Data?
    public var recursive: Bool
    public init(path: String, bookmark: Data? = nil, recursive: Bool = true) {
        self.id = UUID(); self.path = path; self.bookmark = bookmark; self.recursive = recursive
    }
}

public struct Preset: Codable, Identifiable, Equatable, Sendable {
    public var schemaVersion = 1
    public var id: UUID
    public var name: String
    public var folders: [FolderReference] = []
    public var overrides: [String: SettingValue] = [:]
    public var rules: [SizeRule]?
    public var portraitLayout: String?
    public var landscapeLayout: String?
    public var markedPaths: Set<String> = []
    public var lastPath: String?
    public var displayID: UInt32?
    public var sort = "name"
    public init(name: String = "") { self.id = UUID(); self.name = name }
}

public struct ImageItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String { path }
    public var path: String
    public var folderID: UUID
    public var width: Int
    public var height: Int
    public var modified: Date
    public var bytes: Int64
    public var type: String
    public init(path: String, folderID: UUID, width: Int, height: Int, modified: Date, bytes: Int64, type: String) {
        self.path = path; self.folderID = folderID; self.width = width; self.height = height
        self.modified = modified; self.bytes = bytes; self.type = type
    }
    public func included(in settings: Preferences) -> Bool {
        if type == "gif" && !settings[.includeGIF].bool { return false }
        return min(width, height) >= Int(settings[.minShort].number) && max(width, height) >= Int(settings[.minLong].number)
    }
}

public struct ScanResult: Codable, Sendable {
    public var images: [ImageItem] = []
    public var unavailableFolders: [String] = []
    public var errors: [String] = []
    public var date = Date()
    public init() {}
}

public struct KeyBinding: Codable, Equatable, Sendable {
    public var code: UInt16
    public var modifiers: UInt
    public var label: String
    public init(_ code: UInt16, modifiers: UInt = 0, label: String) { self.code = code; self.modifiers = modifiers; self.label = label }
}

public enum PlayerAction: String, CaseIterable, Identifiable {
    case pause, next, previous, slower, faster, mark, undo, filename, filenames, fullscreen, original, zoomIn, zoomOut, reveal, exit
    public var id: String { rawValue }
    public var initial: KeyBinding {
        switch self {
        case .pause: return .init(49, label: "Space")
        case .next: return .init(124, label: "→")
        case .previous: return .init(123, label: "←")
        case .slower: return .init(126, label: "↑")
        case .faster: return .init(125, label: "↓")
        case .mark: return .init(7, label: "X")
        case .undo: return .init(6, modifiers: 1 << 20, label: "⌘Z")
        case .filename: return .init(34, label: "I")
        case .filenames: return .init(34, modifiers: 1 << 17, label: "⇧I")
        case .fullscreen: return .init(3, label: "F")
        case .original: return .init(18, label: "1")
        case .zoomIn: return .init(24, label: "+")
        case .zoomOut: return .init(27, label: "−")
        case .reveal: return .init(15, modifiers: 1 << 20, label: "⌘R")
        case .exit: return .init(53, label: "Esc")
        }
    }
}
