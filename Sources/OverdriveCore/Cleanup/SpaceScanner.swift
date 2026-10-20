import Foundation

/// One folder (or package, or file) in a size tree.
public final class SpaceNode: @unchecked Sendable, Identifiable {
    public let id: String
    public let url: URL
    public let name: String
    public private(set) var size: UInt64 = 0
    public private(set) var fileCount = 0
    public let isDirectory: Bool
    public let isPackage: Bool
    public private(set) var children: [SpaceNode] = []
    public weak var parent: SpaceNode?

    init(url: URL, isDirectory: Bool, isPackage: Bool, parent: SpaceNode?) {
        self.id = url.path
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.parent = parent
    }

    private var largestFiles: [SpaceNode] = []
    static let largestFilesKept = 8
    static let largestFileMinimum: UInt64 = 1_000_000

    func add(child: SpaceNode) { children.append(child) }
    func account(bytes: UInt64) { size += bytes; fileCount += 1 }

    /// Remembers the folder's biggest files (not counted again; `account` already did) so they show up
    /// beside subfolders. Only a handful per folder are kept, so memory stays flat on huge trees.
    func noteFile(_ url: URL, bytes: UInt64) {
        guard bytes >= Self.largestFileMinimum else { return }
        if largestFiles.count >= Self.largestFilesKept, let smallest = largestFiles.last, smallest.size >= bytes { return }
        let leaf = SpaceNode(url: url, isDirectory: false, isPackage: false, parent: self)
        leaf.size = bytes
        leaf.fileCount = 1
        largestFiles.append(leaf)
        largestFiles.sort { $0.size > $1.size }
        if largestFiles.count > Self.largestFilesKept { largestFiles.removeLast() }
    }

    /// Drops a child after it was moved to the Trash, keeping ancestor totals honest.
    public func remove(child: SpaceNode) {
        guard let index = children.firstIndex(where: { $0.id == child.id }) else { return }
        children.remove(at: index)
        var cursor: SpaceNode? = self
        while let n = cursor {
            n.size = n.size >= child.size ? n.size - child.size : 0
            n.fileCount = max(0, n.fileCount - child.fileCount)
            cursor = n.parent
        }
    }

    /// Largest children first; small ones beyond `limit` are summarized as one "Other" node.
    public func topChildren(limit: Int = 24) -> [SpaceNode] {
        let sorted = children.sorted { $0.size > $1.size }
        guard sorted.count > limit else { return sorted }
        let rest = sorted[limit...]
        let other = SpaceNode(url: url.appending(path: "…"), isDirectory: false, isPackage: false, parent: self)
        other.size = rest.reduce(0) { $0 + $1.size }
        other.fileCount = rest.reduce(0) { $0 + $1.fileCount }
        return Array(sorted.prefix(limit)) + [other]
    }

    public var isSummary: Bool { name == "…" }

    public var ancestry: [SpaceNode] {
        var chain: [SpaceNode] = []
        var cursor: SpaceNode? = self
        while let n = cursor { chain.insert(n, at: 0); cursor = n.parent }
        return chain
    }

    func finish() {
        children.append(contentsOf: largestFiles)
        largestFiles.removeAll()
        children.sort { $0.size > $1.size }
        for c in children { c.finish() }
    }
}

/// Builds a size tree for a folder. Packages (apps, libraries, bundles) count as single leaves,
/// folders deeper than `maxDepth` fold into their ancestor, other volumes mounted inside the
/// tree are skipped, and symlinks are never followed.
public final class SpaceScanner: @unchecked Sendable {
    public let root: URL
    public let maxDepth: Int
    private let lock = NSLock()
    private var cancelled = false

    public init(root: URL, maxDepth: Int = 6) {
        self.root = root
        self.maxDepth = maxDepth
    }

    public func cancel() { lock.withLock { cancelled = true } }
    public var isCancelled: Bool { lock.withLock { cancelled } }

    public func scan(progress: (Int, UInt64) -> Void) -> SpaceNode {
        let rootNode = SpaceNode(url: root, isDirectory: true, isPackage: false, parent: nil)
        // Keyed by path components relative to the root, so the enumerator's URL form never matters.
        var nodes: [[String]: SpaceNode] = [[]: rootNode]
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey,
                                      .isVolumeKey, .totalFileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [],
                                                              errorHandler: { _, _ in true }) else { return rootNode }
        // The enumerator may hand back resolved paths (/private/var for /var), so measure the root's
        // depth from its first item, which is always a direct child.
        var rootDepth = -1
        var seen = 0
        let keySet = Set(keys)

        /// The nearest tracked ancestor of a relative path (the root at worst).
        func owner(of relative: ArraySlice<String>) -> SpaceNode {
            var slice = relative
            while !slice.isEmpty {
                if let n = nodes[Array(slice)] { return n }
                slice = slice.dropLast()
            }
            return rootNode
        }

        for case let url as URL in enumerator {
            seen += 1
            if seen % 2000 == 0 {
                if isCancelled { break }
                progress(seen, rootNode.size)
            }
            guard let v = try? url.resourceValues(forKeys: keySet) else { continue }
            if v.isSymbolicLink == true { continue }
            if rootDepth < 0 { rootDepth = url.pathComponents.count - 1 }
            let relative = Array(url.pathComponents.dropFirst(rootDepth))
            guard !relative.isEmpty else { continue }

            if v.isDirectory == true {
                if v.isVolume == true {
                    enumerator.skipDescendants()
                    continue
                }
                let parent = owner(of: relative.dropLast())
                // Inside a package everything belongs to the package; deep folders fold into their ancestor.
                guard !parent.isPackage, nodes[Array(relative.dropLast())] != nil || relative.count == 1,
                      relative.count <= maxDepth || v.isPackage == true else { continue }
                let node = SpaceNode(url: url, isDirectory: true, isPackage: v.isPackage == true, parent: parent)
                parent.add(child: node)
                nodes[relative] = node
                continue
            }
            guard v.isRegularFile == true else { continue }
            let bytes = UInt64(v.totalFileAllocatedSize ?? 0)
            let folder = owner(of: relative.dropLast())
            if !folder.isPackage { folder.noteFile(url, bytes: bytes) }
            var cursor: SpaceNode? = folder
            while let n = cursor {
                n.account(bytes: bytes)
                cursor = n.parent
            }
        }
        progress(seen, rootNode.size)
        rootNode.finish()
        return rootNode
    }
}
