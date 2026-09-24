import Foundation

public enum ExportFilename {
    public static func safeBaseName(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>\n\r\t")
        let replaced = title.components(separatedBy: forbidden).filter { !$0.isEmpty }.joined(separator: "-")
        let cleaned = replaced.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let limited = String(cleaned.prefix(120))
        return limited.isEmpty ? "YouTube Transcript" : limited
    }
}
