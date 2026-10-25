import Foundation

/// Whether a newer release of this app exists, from GitHub's latest-release
/// endpoint — the same source the core's own update check reads, for its own
/// repo. The cask follows each tag, so a newer tag means `brew upgrade` has it.
public enum UpdateCheck {
    static let url = URL(string: "https://api.github.com/repos/afitzgerald/moomux-mac/releases/latest")!

    /// The newest tag when it is newer than `current`, else nil. A failed
    /// fetch is nil too: no badge beats a wrong one.
    public static func newerVersion(than current: String) async -> String? {
        guard !current.isEmpty,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let tag = latestTag(data)
        else { return nil }
        return newer(tag, than: current)
    }

    private static func latestTag(_ data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["tag_name"] as? String
    }

    static func newer(_ tag: String, than current: String) -> String? {
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return latest.compare(current, options: .numeric) == .orderedDescending ? latest : nil
    }

    public static func demo() {
        assert(newer("v0.0.100", than: "0.0.99") == "0.0.100", "numeric, not lexical")
        assert(newer("v0.0.99", than: "0.0.99") == nil)
        assert(newer("0.0.98", than: "0.0.99") == nil)
    }
}
