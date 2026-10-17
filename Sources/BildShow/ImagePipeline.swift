import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import MetalKit
import BildShowCore

final class PreparedFrame: @unchecked Sendable {
    let texture: MTLTexture
    let rect: SIMD4<Float>
    let edges: SIMD4<Float>
    let feather: Float
    let frameCount: Int
    let frameDelay: Double
    let cost: Int
    init(texture: MTLTexture, rect: SIMD4<Float>, edges: SIMD4<Float>, feather: Float, frameCount: Int, frameDelay: Double) {
        self.texture = texture; self.rect = rect; self.edges = edges; self.feather = feather
        self.frameCount = frameCount; self.frameDelay = frameDelay; self.cost = texture.width * texture.height * 4
    }
}

enum ImageFailure: LocalizedError {
    case unreadable, timeout, renderer
    var errorDescription: String? {
        switch self {
        case .unreadable: return L("Bilden kunde inte läsas", "The image could not be read")
        case .timeout: return L("Inläsningen tog för lång tid", "Image loading timed out")
        case .renderer: return L("Bildrendering misslyckades", "Image rendering failed")
        }
    }
}

private final class LoadGate: @unchecked Sendable {
    private let lock = NSLock()
    private var complete = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if complete { return false }; complete = true; return true }
}

final class ImagePipeline: @unchecked Sendable {
    static let shared = ImagePipeline()
    let device: MTLDevice
    let context: CIContext
    let cache = NSCache<NSString, PreparedFrame>()
    private let workers = OperationQueue()
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private init() {
        device = MTLCreateSystemDefaultDevice()!
        context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        workers.maxConcurrentOperationCount = 3; workers.qualityOfService = .userInitiated
        cache.totalCostLimit = min(768 * 1024 * 1024, Int(ProcessInfo.processInfo.physicalMemory / 24))
    }
    func clear() { cache.removeAllObjects() }
    func load(_ item: ImageItem, settings: Preferences, size: CGSize, frame: Int = 0, overrideScale: Double? = nil) async throws -> PreparedFrame {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let signature = (try? encoder.encode(settings)).map { $0.hashValue } ?? 0
        let key = "\(item.path)|\(item.modified.timeIntervalSince1970)|\(item.bytes)|\(Int(size.width))x\(Int(size.height))|\(signature)|\(frame)|\(overrideScale ?? -1)"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        return try await withCheckedThrowingContinuation { continuation in
            let gate = LoadGate()
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 4) {
                if gate.claim() { continuation.resume(throwing: ImageFailure.timeout) }
            }
            workers.addOperation { [self] in
                do {
                    let prepared = try autoreleasepool { try prepare(item, settings: settings, size: size, frame: frame, overrideScale: overrideScale) }
                    cache.setObject(prepared, forKey: key as NSString, cost: prepared.cost)
                    if gate.claim() { continuation.resume(returning: prepared) }
                } catch { if gate.claim() { continuation.resume(throwing: error) } }
            }
        }
    }
    private func prepare(_ item: ImageItem, settings: Preferences, size: CGSize, frame: Int, overrideScale: Double?) throws -> PreparedFrame {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: item.path) as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw ImageFailure.unreadable }
        let animated = item.type == "gif" || item.type == "webp"
        let count = animated ? CGImageSourceGetCount(source) : 1
        guard count > 0 else { throw ImageFailure.unreadable }
        let index = min(frame, count - 1)
        let layout = ImageLayout.calculate(width: Double(item.width), height: Double(item.height), screenWidth: size.width, screenHeight: size.height, settings: settings, overrideScale: overrideScale)
        let pixelLimit = min(8192, max(1, Int(ceil(max(layout.width, layout.height)))))
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: pixelLimit, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { throw ImageFailure.unreadable }
        var image = CIImage(cgImage: decoded)
        let factor = layout.width / image.extent.width
        if abs(factor - 1) > 0.001 {
            switch layout.rule.method {
            case "lanczos":
                let filter = CIFilter.lanczosScaleTransform(); filter.inputImage = image; filter.scale = Float(factor); filter.aspectRatio = 1
                image = filter.outputImage ?? image
            case "bicubic":
                let filter = CIFilter.bicubicScaleTransform(); filter.inputImage = image; filter.scale = Float(factor); filter.aspectRatio = 1
                image = filter.outputImage ?? image
            default: image = image.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
            }
        }
        if layout.scale > 1, layout.rule.sharpening > 0 {
            let filter = CIFilter.sharpenLuminance(); filter.inputImage = image; filter.sharpness = Float(layout.rule.sharpening); filter.radius = 1
            image = filter.outputImage ?? image
        }
        let left = max(0, layout.x), top = max(0, layout.y)
        let right = min(size.width, layout.x + layout.width), bottom = min(size.height, layout.y + layout.height)
        let visibleW = max(1, Int(ceil(right - left))), visibleH = max(1, Int(ceil(bottom - top)))
        let crop = CGRect(x: left - layout.x, y: max(0, layout.height - (bottom - layout.y)), width: Double(visibleW), height: Double(visibleH))
        image = image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        image = image.transformed(by: CGAffineTransform(translationX: 0, y: -Double(visibleH))).transformed(by: CGAffineTransform(scaleX: 1, y: -1))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: visibleW, height: visibleH, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw ImageFailure.renderer }
        context.render(image, to: texture, commandBuffer: nil, bounds: CGRect(x: 0, y: 0, width: visibleW, height: visibleH), colorSpace: colorSpace)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any] ?? [:]
        var delay = 0.1
        for key in ["{GIF}", "{WebP}", "{PNG}"] {
            if let animation = properties[key] as? [String: Any] {
                delay = (animation["UnclampedDelayTime"] as? Double) ?? (animation["DelayTime"] as? Double) ?? delay
            }
        }
        return PreparedFrame(texture: texture,
            rect: SIMD4(Float(left / size.width), Float(top / size.height), Float(Double(visibleW) / size.width), Float(Double(visibleH) / size.height)),
            edges: SIMD4(layout.x > 0.5 ? 1 : 0, layout.y > 0.5 ? 1 : 0, layout.x + layout.width < size.width - 0.5 ? 1 : 0, layout.y + layout.height < size.height - 0.5 ? 1 : 0),
            feather: settings[.feather].bool ? Float(min(layout.width, layout.height) * layout.rule.featherPercent / 100) : 0,
            frameCount: count, frameDelay: max(0.02, delay))
    }
}
