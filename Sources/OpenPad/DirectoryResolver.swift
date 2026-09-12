import Foundation

enum DirectoryResolver {
    private static var searchRoots: [String] {
        [
            NSHomeDirectory() + "/projects",
            NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs",
            NSHomeDirectory(),
        ]
    }

    /// Subdirs of the fixed roots matching `query` (case-insensitive substring).
    static func candidates(matching query: String) -> [String] {
        let fm = FileManager.default
        var seen = Set<String>()
        var out: [String] = []
        for root in searchRoots {
            guard let children = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for child in children where !child.hasPrefix(".") {
                let path = (root as NSString).appendingPathComponent(child)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                guard query.isEmpty || child.localizedCaseInsensitiveContains(query) else { continue }
                if seen.insert(path).inserted { out.append(path) }
            }
        }
        return out
    }

    /// mdfind fallback for folders anywhere on disk.
    static func spotlight(matching query: String) -> [String] {
        guard !query.isEmpty else { return [] }
        let p = Process()
        let out = Pipe()
        p.executableURL = URL(filePath: "/usr/bin/mdfind")
        p.arguments = ["-name", query, "kMDItemContentType == 'public.folder'"]
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        p.waitUntilExit()
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(separator: "\n")
            .map(String.init)
            .prefix(10)
            .map { $0 }
    }

    /// Resolve "say where to work" → a directory. Order: recents, known roots,
    /// Spotlight. Returns nil if nothing matches (caller offers typed path).
    static func resolve(_ query: String, recents: [ServerEntry]) -> String? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = recents.first(where: {
            $0.directory.lastPathComponent.localizedCaseInsensitiveCompare(q) == .orderedSame
        }) {
            return exact.directory
        }
        if let first = candidates(matching: q).first { return first }
        return spotlight(matching: q).first
    }
}
