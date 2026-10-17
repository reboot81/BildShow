import Foundation
import ImageIO
import UniformTypeIdentifiers
import BildShowCore

// Generate size samples once, using the same source image without changing its proportions.
enum DemoImages {
    static func prepare(source: URL) -> [ImageItem] {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("BildShow/Demo", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let input = CGImageSourceCreateWithURL(source as CFURL, nil) else { return [] }
            for (name, size) in [("01 – Original", 4096), ("02 – Medium", 960), ("03 – Small", 360)] {
                let output = directory.appendingPathComponent(name).appendingPathExtension("png")
                if FileManager.default.fileExists(atPath: output.path) { continue }
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: size]
                guard let image = CGImageSourceCreateThumbnailAtIndex(input, 0, options as CFDictionary), let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else { continue }
                CGImageDestinationAddImage(destination, image, nil)
                CGImageDestinationFinalize(destination)
            }
            return Catalog.scan([FolderReference(path: directory.path)]).images
        } catch { return [] }
    }
}
