import Foundation

public struct LargeFile: Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let size: UInt64
    public let modified: Date?
}

/// Walks a folder tree for big files, staying on the starting volume (so mounted network
/// homes and disk images are not crawled) and skipping dependency folders nobody deletes by hand.
public final class LargeFileScanner: @unchecked Sendable {
    public let root: URL
    public let minimumSize: UInt64
    public let excluded: [String]
    public static let skippedFolderNames: Set<String> = ["node_modules", ".git", ".build", "DerivedData"]

    private let lock = NSLock()
    private var cancelled = false

    public init(root: URL, minimumSize: UInt64, excluded: [URL]) {
        self.root = root
        self.minimumSize = minimumSize
        self.excluded = excluded.map { $0.standardizedFileURL.path }
    }

    public static func homeScanner(minimumSize: UInt64) -> LargeFileScanner {
        let home = Paths.home
        return LargeFileScanner(root: home, minimumSize: minimumSize,
                                excluded: [home.appending(path: "Library"), home.appending(path: ".Trash")])
    }

    public func cancel() {
        lock.withLock { cancelled = true }
    }

    public var isCancelled: Bool { lock.withLock { cancelled } }

    public func scan(limit: Int = 300, progress: (Int) -> Void) -> [LargeFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isVolumeKey, .isSymbolicLinkKey,
                                      .totalFileAllocatedSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [],
                                                              errorHandler: { _, _ in true }) else { return [] }
        var found: [LargeFile] = []
        var seen = 0
        let keySet = Set(keys)
        for case let url as URL in enumerator {
            seen += 1
            if seen % 2000 == 0 {
                if isCancelled { break }
                progress(seen)
            }
            guard let v = try? url.resourceValues(forKeys: keySet) else { continue }
            if v.isDirectory == true {
                if v.isVolume == true || Self.skippedFolderNames.contains(url.lastPathComponent)
                    || excluded.contains(url.standardizedFileURL.path) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard v.isRegularFile == true, v.isSymbolicLink != true else { continue }
            let size = UInt64(v.totalFileAllocatedSize ?? 0)
            if size >= minimumSize {
                found.append(LargeFile(url: url, size: size, modified: v.contentModificationDate))
            }
        }
        progress(seen)
        return Array(found.sorted { $0.size > $1.size }.prefix(limit))
    }
}
