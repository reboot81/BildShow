import Foundation

public enum FolderSelection {
    public static func isIncluded(_ path: String, in folders: [FolderReference]) -> Bool {
        let target = normalized(path)
        if folders.contains(where: { normalized($0.path) == target }) { return true }
        return coveringFolder(for: target, in: folders) != nil
    }

    public static func toggled(_ path: String, bookmark: Data?, in folders: [FolderReference]) -> [FolderReference] {
        let target = normalized(path)
        var result = folders
        let wasIncluded = isIncluded(target, in: result)

        if wasIncluded {
            result.removeAll { reference in
                let selected = normalized(reference.path)
                return selected == target || isDescendant(selected, of: target)
            }
            if let index = nearestRecursiveAncestorIndex(for: target, in: result),
               let relative = relativePath(target, under: result[index].path), !relative.isEmpty {
                var exclusions = result[index].excludedRelativePaths ?? []
                exclusions = exclusions.filter { !isDescendant($0, of: relative) }
                exclusions.insert(relative)
                result[index].excludedRelativePaths = exclusions
            }
        } else {
            result.removeAll { isDescendant(normalized($0.path), of: target) }
            result.append(FolderReference(path: target, bookmark: bookmark, recursive: true))
        }
        return result
    }

    public static func isExcluded(_ path: String, from root: FolderReference, resolvedRootPath: String? = nil) -> Bool {
        let base = resolvedRootPath ?? root.path
        guard let relative = relativePath(path, under: base), !relative.isEmpty else { return false }
        return (root.excludedRelativePaths ?? []).contains { exclusion in
            relative == exclusion || isDescendant(relative, of: exclusion)
        }
    }

    public static func relativePath(_ path: String, under root: String) -> String? {
        let targetComponents = URL(fileURLWithPath: normalized(path)).pathComponents
        let rootComponents = URL(fileURLWithPath: normalized(root)).pathComponents
        guard targetComponents.count >= rootComponents.count,
              Array(targetComponents.prefix(rootComponents.count)) == rootComponents else { return nil }
        return targetComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private static func coveringFolder(for path: String, in folders: [FolderReference]) -> FolderReference? {
        folders
            .filter { reference in
                reference.recursive && isDescendant(path, of: normalized(reference.path)) &&
                !isExcluded(path, from: reference)
            }
            .max { normalized($0.path).count < normalized($1.path).count }
    }

    private static func nearestRecursiveAncestorIndex(for path: String, in folders: [FolderReference]) -> Int? {
        folders.indices
            .filter { folders[$0].recursive && isDescendant(path, of: normalized(folders[$0].path)) }
            .max { normalized(folders[$0].path).count < normalized(folders[$1].path).count }
    }

    private static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func isDescendant(_ path: String, of root: String) -> Bool {
        guard path != root else { return false }
        return path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}
