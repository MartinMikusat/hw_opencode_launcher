import Foundation

enum ServerManager {
    /// Find the opencode binary: well-known installs first, login shell PATH as fallback.
    static func findBinary() -> String? {
        let candidates = [
            NSHomeDirectory() + "/.opencode/bin/opencode",
            "/opt/homebrew/bin/opencode",
            "/usr/local/bin/opencode",
        ]
        if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return hit
        }
        let p = Process()
        let out = Pipe()
        p.executableURL = URL(filePath: "/bin/zsh")
        p.arguments = ["-lc", "command -v opencode"]
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let path = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return p.terminationStatus == 0 && !path.isEmpty ? path : nil
    }

    private static func port(for directory: String, offset: Int = 0) -> Int {
        var h: UInt64 = 1469598103934665603
        for b in directory.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return 4100 + Int(h % 800) + offset
    }

    /// True if a server answering on `port` reports `directory` as its cwd.
    private static func probe(port: Int, directory: String) async -> Bool {
        let client = OpencodeClient(baseURL: URL(string: "http://127.0.0.1:\(port)")!)
        guard let info = try? await client.pathInfo() else { return false }
        let lhs = (info.directory as NSString).resolvingSymlinksInPath
        let rhs = (directory as NSString).resolvingSymlinksInPath
        return lhs == rhs
    }

    /// Return a live client+port for `directory`, spawning `opencode serve`
    /// detached if needed. Servers outlive the app.
    static func ensureServer(directory: String) async throws -> (client: OpencodeClient, port: Int) {
        guard FileManager.default.fileExists(atPath: directory) else {
            throw OCError.http(0, "directory does not exist: \(directory)")
        }
        for offset in 0..<8 {
            let p = port(for: directory, offset: offset)
            let client = OpencodeClient(baseURL: URL(string: "http://127.0.0.1:\(p)")!)
            if await probe(port: p, directory: directory) {
                return (client, p)
            }
            if (try? await client.pathInfo()) != nil { continue } // other project's server
            guard let bin = findBinary() else {
                throw OCError.http(0, "opencode binary not found (install: brew install opencode)")
            }
            let proc = Process()
            proc.executableURL = URL(filePath: bin)
            proc.arguments = ["serve", "--port", String(p), "--hostname", "127.0.0.1"]
            proc.currentDirectoryURL = URL(filePath: directory)
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try proc.run()
            for _ in 0..<80 where !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                if await probe(port: p, directory: directory) {
                    return (client, p)
                }
            }
        }
        throw OCError.http(0, "could not start opencode server for \(directory)")
    }
}
