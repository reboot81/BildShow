import Foundation
import ImageIO
import BildShowCore

enum Catalog {
    static let extensions: Set<String> = ["jpg", "jpeg", "jpe", "png", "heic", "heif", "tif", "tiff", "webp", "gif", "bmp", "avif"]
    static func scan(_ folders: [FolderReference], sort: String = "name") -> ScanResult {
        let access = ScopedAccess(folders)
        var result = ScanResult(), seen = Set<String>()
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        for (folder, root) in zip(folders, access.urls) {
            guard FileManager.default.isReadableFile(atPath: root.path) else { result.unavailableFolders.append(root.path); continue }
            var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
            if !folder.recursive { options.insert(.skipsSubdirectoryDescendants) }
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: options, errorHandler: { url, error in
                if result.errors.count < 100 { result.errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
                return true
            }) else { result.unavailableFolders.append(root.path); continue }
            var batch: [ImageItem] = []
            for case let url as URL in enumerator {
                if Task<Never, Never>.isCancelled { return result }
                let ext = url.pathExtension.lowercased()
                guard extensions.contains(ext) else { continue }
                let canonical = url.resolvingSymlinksInPath().standardizedFileURL.path
                guard seen.insert(canonical).inserted else { continue }
                autoreleasepool {
                    guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return }
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                          var w = properties[kCGImagePropertyPixelWidth] as? Int,
                          var h = properties[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0 else {
                        if result.errors.count < 100 { result.errors.append(url.path) }
                        return
                    }
                    let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
                    if (5...8).contains(orientation) { swap(&w, &h) }
                    batch.append(ImageItem(path: canonical, folderID: folder.id, width: w, height: h,
                                           modified: values.contentModificationDate ?? .distantPast, bytes: Int64(values.fileSize ?? 0), type: ext))
                }
            }
            batch.sort {
                if sort == "date", $0.modified != $1.modified { return $0.modified < $1.modified }
                return $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }
            result.images += batch
        }
        withExtendedLifetime(access) {}
        return result
    }
}
