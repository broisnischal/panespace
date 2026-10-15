import Foundation

/// i3 criteria: `[app="^Safari$" title="(?i)preferences" floating]`.
/// `class`/`instance` are accepted as aliases of `app` so i3 rules paste in unchanged.
public struct Criteria {
    public var app: NSRegularExpression?
    public var bundleID: NSRegularExpression?
    public var title: NSRegularExpression?
    public var workspace: NSRegularExpression?
    public var floating: Bool?

    public init() {}

    /// `s` is the text between the brackets.
    public static func parse(_ s: String) throws -> Criteria {
        var c = Criteria()
        let chars = Array(s)
        var i = 0
        func skipSpace() { while i < chars.count && chars[i].isWhitespace { i += 1 } }
        while true {
            skipSpace()
            guard i < chars.count else { break }
            var key = ""
            while i < chars.count, chars[i].isLetter || chars[i] == "_" { key.append(chars[i]); i += 1 }
            guard !key.isEmpty else { throw ParseError("bad criteria near '\(String(chars[i...]))'") }
            skipSpace()
            var value: String?
            if i < chars.count, chars[i] == "=" {
                i += 1
                skipSpace()
                var v = ""
                if i < chars.count, chars[i] == "\"" || chars[i] == "'" {
                    let q = chars[i]
                    i += 1
                    while i < chars.count, chars[i] != q {
                        if chars[i] == "\\", i + 1 < chars.count, chars[i + 1] == q { i += 1 }
                        v.append(chars[i])
                        i += 1
                    }
                    i += 1
                } else {
                    while i < chars.count, !chars[i].isWhitespace { v.append(chars[i]); i += 1 }
                }
                value = v
            }
            func re() throws -> NSRegularExpression {
                guard let value else { throw ParseError("criterion '\(key)' needs a value") }
                do { return try NSRegularExpression(pattern: value) } catch { throw ParseError("bad regex '\(value)'") }
            }
            switch key.lowercased() {
            case "app", "class", "instance", "app_name": c.app = try re()
            case "app_id", "bundle", "bundle_id": c.bundleID = try re()
            case "title": c.title = try re()
            case "workspace": c.workspace = try re()
            case "floating": c.floating = true
            case "tiling": c.floating = false
            default: throw ParseError("unknown criterion '\(key)'")
            }
        }
        return c
    }

    public func matches(_ w: WindowNode) -> Bool {
        func m(_ re: NSRegularExpression?, _ s: String) -> Bool {
            guard let re else { return true }
            return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
        }
        if let f = floating, f != w.isFloating { return false }
        return m(app, w.info.app) && m(bundleID, w.info.bundleID) && m(title, w.info.title)
            && m(workspace, w.workspace?.name ?? "")
    }
}

public struct ParseError: Error, CustomStringConvertible, Equatable {
    public let description: String
    public init(_ d: String) { description = d }
}
