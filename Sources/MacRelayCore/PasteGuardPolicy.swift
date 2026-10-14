import Foundation

public enum PasteGuardPolicy {
    public static func shouldSuppress(
        keyCode: Int64, sourcePID: Int32, wisprPIDs: Set<Int32>, frontmostApp: String?
    ) -> Bool {
        keyCode == 9 && sourcePID > 0 && wisprPIDs.contains(sourcePID)
            && frontmostApp == "com.apple.ScreenSharing"
    }
    public static func remoteTitle(_ title: String, matches name: String) -> Bool {
        func normalized(_ string: String) -> String {
            string.replacingOccurrences(of: "’", with: "'")
                .folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let title = normalized(title)
        let name = normalized(name)
        return !name.isEmpty
            && (title == name || title.hasPrefix(name + " (") || title.hasPrefix(name + " — "))
    }
}
