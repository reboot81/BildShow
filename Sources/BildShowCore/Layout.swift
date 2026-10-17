import Foundation

public struct ImageLayout: Equatable, Sendable {
    public var scale: Double
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var rule: SizeRule
    public static func calculate(width: Double, height: Double, screenWidth: Double, screenHeight: Double, settings: Preferences, overrideScale: Double? = nil) -> ImageLayout {
        guard width > 0, height > 0, screenWidth > 0, screenHeight > 0 else {
            return .init(scale: 1, x: 0, y: 0, width: 1, height: 1, rule: SizeRule.defaults[0])
        }
        let fit = min(screenWidth / width, screenHeight / height)
        let fill = max(screenWidth / width, screenHeight / height)
        let orientation = height > width ? settings.portraitLayout : settings.landscapeLayout
        let mode = orientation == "inherit" ? settings[.layout].text : orientation
        var desired: Double
        switch mode {
        case "fill": desired = fill
        case "width": desired = screenWidth / width
        case "height": desired = screenHeight / height
        case "smart":
            let loss = 1 - (screenWidth * screenHeight) / (width * height * fill * fill)
            desired = loss <= settings[.cropLimit].number / 100 ? fill : fit
        default: desired = fit
        }
        if let overrideScale { desired = overrideScale }
        let rules = settings.rules.sorted { $0.upperScale < $1.upperScale }
        var rule = rules.first(where: { desired <= $0.upperScale }) ?? rules.last ?? SizeRule.defaults[3]
        rule.maxScale = min(8, max(1, rule.maxScale.isFinite ? rule.maxScale : 3))
        rule.sharpening = min(1, max(0, rule.sharpening.isFinite ? rule.sharpening : 0))
        rule.featherPercent = min(20, max(0, rule.featherPercent.isFinite ? rule.featherPercent : 0))
        let scale = overrideScale == nil ? min(desired, max(1, rule.maxScale)) : desired
        let w = width * scale, h = height * scale
        let anchor = w > screenWidth || h > screenHeight ? settings[.cropAnchor].text : settings[.placement].text
        var x = (screenWidth - w) / 2, y = (screenHeight - h) / 2
        switch anchor {
        case "left": x = 0
        case "right": x = screenWidth - w
        case "top": y = 0
        case "bottom": y = screenHeight - h
        default: break
        }
        return .init(scale: scale, x: x, y: y, width: w, height: h, rule: rule)
    }
}

public enum PlaybackOrder {
    public static func reconcile(saved: [String], available: [String], random: Bool) -> [String] {
        let set = Set(available)
        var seen = Set<String>()
        let kept = saved.filter { set.contains($0) && seen.insert($0).inserted }
        var added = available.filter { seen.insert($0).inserted }
        if !random { return Array(NSOrderedSet(array: available)) as? [String] ?? available }
        added.shuffle()
        return kept + added
    }
    public static func nextRound(_ available: [String], random: Bool, previous: String?) -> [String] {
        var result = Array(NSOrderedSet(array: available)) as? [String] ?? available
        if random { result.shuffle() }
        if random, result.count > 1, result.first == previous { result.swapAt(0, 1) }
        return result
    }
}
