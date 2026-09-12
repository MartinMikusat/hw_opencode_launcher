import Foundation

extension String {
    var lastPathComponent: String { URL(fileURLWithPath: self).lastPathComponent }
    var expandingTildeInPath: String {
        if self == "~" { return NSHomeDirectory() }
        if hasPrefix("~/") { return NSHomeDirectory() + dropFirst() }
        return self
    }
    var resolvingSymlinksInPath: String {
        URL(fileURLWithPath: self).resolvingSymlinksInPath().path
    }
    func appendingPathComponent(_ c: String) -> String {
        URL(fileURLWithPath: self).appendingPathComponent(c).path
    }
    var shellEscaped: String { "'" + replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
