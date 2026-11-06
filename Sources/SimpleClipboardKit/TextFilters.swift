import AppKit

/// A text change applied to a clip before pasting ("paste special"). The set follows Pastebot's built-in filters,
/// without the ones that need heuristics or other services (translation, emoji, smart punctuation, Markdown to HTML).
struct TextFilter: Equatable {
    enum Group: String, CaseIterable {
        case textAndWriting = "Text & Writing"
        case developer = "Developer"
        case webAndMarkdown = "Web & Markdown"
    }

    let id: String
    let name: String
    let group: Group
    let summary: String
    /// Returns nil when the filter does not apply, for example Base64 Decode on text that is not Base64.
    let apply: (String) -> String?

    static func == (left: TextFilter, right: TextFilter) -> Bool { left.id == right.id }

    static func named(_ id: String) -> TextFilter? { all.first { $0.id == id } }

    /// Filters whose name, group or summary contains the query, in list order.
    static func matching(_ query: String) -> [TextFilter] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) || $0.group.rawValue.localizedCaseInsensitiveContains(trimmed)
                || $0.summary.localizedCaseInsensitiveContains(trimmed)
        }
    }

    static let all: [TextFilter] = [
        // Text & Writing
        TextFilter(id: "plain-text", name: "Convert to Plain Text", group: .textAndWriting,
                   summary: "Text only, no fonts, colors or links") { $0 },
        TextFilter(id: "single-line", name: "Single Line", group: .textAndWriting,
                   summary: "Join all lines into one") { TextTransforms.singleLine($0) },
        TextFilter(id: "trim-whitespace", name: "Trim Whitespace", group: .textAndWriting,
                   summary: "Remove spaces and tabs at both ends of each line") { TextTransforms.trimLines($0) },
        TextFilter(id: "normalize-whitespace", name: "Normalize Whitespace", group: .textAndWriting,
                   summary: "Single spaces, trimmed lines, no empty lines") { TextTransforms.normalizeWhitespace($0) },
        TextFilter(id: "uppercase", name: "Convert to Uppercase", group: .textAndWriting,
                   summary: "ALL CAPITALS") { $0.uppercased() },
        TextFilter(id: "lowercase", name: "Convert to Lowercase", group: .textAndWriting,
                   summary: "all small letters") { $0.lowercased() },
        TextFilter(id: "titlecase", name: "Convert to Titlecase", group: .textAndWriting,
                   summary: "Capital First Letter Of Each Word") { TextTransforms.titlecase($0) },
        TextFilter(id: "straight-punctuation", name: "Convert to Straight Punctuation", group: .textAndWriting,
                   summary: "Curly quotes, dashes and ellipses to plain characters") { TextTransforms.straightPunctuation($0) },
        TextFilter(id: "sort-lines", name: "Sort Lines", group: .textAndWriting,
                   summary: "Lines in alphabetical order") { TextTransforms.sortLines($0) },
        TextFilter(id: "remove-duplicate-lines", name: "Remove Duplicate Lines", group: .textAndWriting,
                   summary: "Keep the first of each repeated line") { TextTransforms.removeDuplicateLines($0) },
        TextFilter(id: "remove-list-numbering", name: "Remove List Numbering", group: .textAndWriting,
                   summary: "Drop leading \"1. \" or \"2) \" from each line") { TextTransforms.removeListNumbering($0) },
        // Developer
        TextFilter(id: "url-encode", name: "URL Encode", group: .developer,
                   summary: "Percent-encode for URLs") { TextTransforms.urlEncode($0) },
        TextFilter(id: "url-decode", name: "URL Decode", group: .developer,
                   summary: "Decode percent-encoding") { $0.removingPercentEncoding },
        TextFilter(id: "base64-encode", name: "Base64 Encode", group: .developer,
                   summary: "Text as Base64") { Data($0.utf8).base64EncodedString() },
        TextFilter(id: "base64-decode", name: "Base64 Decode", group: .developer,
                   summary: "Base64 back to text") { TextTransforms.base64Decode($0) },
        TextFilter(id: "hex-encode", name: "Hex Encode", group: .developer,
                   summary: "Text as hexadecimal bytes") { $0.utf8.map { String(format: "%02x", $0) }.joined() },
        TextFilter(id: "hex-decode", name: "Hex Decode", group: .developer,
                   summary: "Hexadecimal bytes back to text") { TextTransforms.hexDecode($0) },
        TextFilter(id: "html-entity-encode", name: "HTML Entity Encode", group: .developer,
                   summary: "Escape < > & and quotes for HTML") { TextTransforms.htmlEntityEncode($0) },
        TextFilter(id: "html-entity-decode", name: "HTML Entity Decode", group: .developer,
                   summary: "&amp; and &#8212; back to characters") { TextTransforms.htmlEntityDecode($0) },
        TextFilter(id: "json-string-escape", name: "Escape for JSON String", group: .developer,
                   summary: "Escape quotes, backslashes and line breaks") { TextTransforms.jsonStringEscape($0) },
        TextFilter(id: "format-json", name: "Format JSON", group: .developer,
                   summary: "Indented JSON with sorted keys") { TextTransforms.formatJSON($0) },
        TextFilter(id: "slugify", name: "Slugify", group: .developer,
                   summary: "lowercase-words-with-hyphens") { TextTransforms.slugify($0) },
        TextFilter(id: "snake-case", name: "To snake_case", group: .developer,
                   summary: "words_with_underscores") { TextTransforms.snakeCase($0) },
        TextFilter(id: "camel-case", name: "To camelCase", group: .developer,
                   summary: "wordsWithCapitals") { TextTransforms.camelCase($0) },
        // Web & Markdown
        TextFilter(id: "strip-html", name: "Strip HTML", group: .webAndMarkdown,
                   summary: "Remove tags and decode entities") { TextTransforms.stripHTML($0) },
        TextFilter(id: "markdown-link", name: "Markdown Link from URL", group: .webAndMarkdown,
                   summary: "[url](url)") { TextTransforms.markdownLink($0) },
        TextFilter(id: "markdown-blockquote", name: "Markdown Blockquote", group: .webAndMarkdown,
                   summary: "Prefix each line with \"> \"") { TextTransforms.lines($0).map { "> " + $0 }.joined(separator: "\n") },
        TextFilter(id: "extract-urls", name: "Extract URLs", group: .webAndMarkdown,
                   summary: "Only the URLs, one per line") { TextTransforms.extractURLs($0) },
        TextFilter(id: "extract-email-addresses", name: "Extract Email Addresses", group: .webAndMarkdown,
                   summary: "Only the email addresses, one per line") { TextTransforms.extractEmailAddresses($0) },
        TextFilter(id: "create-list", name: "Create List", group: .webAndMarkdown,
                   summary: "Each line as <li> in a <ul>") { TextTransforms.createList($0) },
        TextFilter(id: "paragraph-tags", name: "Wrap in Paragraph Tags", group: .webAndMarkdown,
                   summary: "<p>text</p>") { "<p>" + $0 + "</p>" },
    ]
}

/// The text work behind the filters, and plain text extraction from stored clips.
enum TextTransforms {
    static func lines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
    }

    static func singleLine(_ text: String) -> String {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func trimLines(_ text: String) -> String {
        lines(text).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t")) }.joined(separator: "\n")
    }

    static func normalizeWhitespace(_ text: String) -> String {
        lines(text).map { line in
            line.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func titlecase(_ text: String) -> String {
        var result = ""
        var atWordStart = true
        for character in text {
            if character.isLetter || character.isNumber {
                result += atWordStart ? character.uppercased() : String(character)
                atWordStart = false
            } else {
                result.append(character)
                atWordStart = character.isWhitespace || character == "-" || character == "/"
            }
        }
        return result
    }

    static func straightPunctuation(_ text: String) -> String {
        var result = text
        for (from, to) in [("\u{2018}", "'"), ("\u{2019}", "'"), ("\u{201A}", "'"), ("\u{201B}", "'"),
                           ("\u{201C}", "\""), ("\u{201D}", "\""), ("\u{201E}", "\""), ("\u{201F}", "\""),
                           ("\u{2014}", "--"), ("\u{2013}", "-"), ("\u{2026}", "..."), ("\u{00A0}", " ")] {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return result
    }

    static func sortLines(_ text: String) -> String {
        let trailingNewline = text.hasSuffix("\n")
        let sorted = lines(trailingNewline ? String(text.dropLast()) : text)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return sorted.joined(separator: "\n") + (trailingNewline ? "\n" : "")
    }

    static func removeDuplicateLines(_ text: String) -> String {
        var seen = Set<String>()
        return lines(text).filter { seen.insert($0).inserted }.joined(separator: "\n")
    }

    static func removeListNumbering(_ text: String) -> String {
        let pattern = try! NSRegularExpression(pattern: "^\\s*\\d+[.)]\\s+")
        return lines(text).map { line in
            pattern.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "")
        }.joined(separator: "\n")
    }

    static func urlEncode(_ text: String) -> String? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed)
    }

    static func base64Decode(_ text: String) -> String? {
        let compact = text.filter { !$0.isWhitespace }
        let padded = compact + String(repeating: "=", count: (4 - compact.count % 4) % 4)
        guard let data = Data(base64Encoded: padded) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func hexDecode(_ text: String) -> String? {
        var compact = text.filter { !$0.isWhitespace }
        if compact.lowercased().hasPrefix("0x") { compact = String(compact.dropFirst(2)) }
        guard !compact.isEmpty, compact.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        var index = compact.startIndex
        while index < compact.endIndex {
            let next = compact.index(index, offsetBy: 2)
            guard let byte = UInt8(compact[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    static func htmlEntityEncode(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}", "mdash": "\u{2014}",
        "ndash": "\u{2013}", "hellip": "\u{2026}", "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}",
        "rdquo": "\u{201D}", "copy": "\u{00A9}", "reg": "\u{00AE}", "trade": "\u{2122}", "bull": "\u{2022}",
        "middot": "\u{00B7}", "times": "\u{00D7}", "deg": "\u{00B0}", "euro": "\u{20AC}", "pound": "\u{00A3}",
    ]

    static func htmlEntityDecode(_ text: String) -> String {
        let pattern = try! NSRegularExpression(pattern: "&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);")
        let source = text as NSString
        var result = ""
        var location = 0
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: location, length: match.range.location - location))
            let name = source.substring(with: match.range(at: 1))
            var replacement: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                replacement = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if name.hasPrefix("#") {
                replacement = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                replacement = namedEntities[name]
            }
            result += replacement ?? source.substring(with: match.range)
            location = match.range.location + match.range.length
        }
        result += source.substring(from: location)
        return result
    }

    static func jsonStringEscape(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 { result += String(format: "\\u%04x", scalar.value) } else { result.unicodeScalars.append(scalar) }
            }
        }
        return result
    }

    static func formatJSON(_ text: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]),
              let data = try? JSONSerialization.data(withJSONObject: object,
                                                     options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Words split at spaces, punctuation and lowercase-to-uppercase changes ("fooBar baz" is foo, Bar, baz).
    static func words(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previous: Character?
        for character in text.folding(options: .diacriticInsensitive, locale: nil) {
            if character.isLetter || character.isNumber {
                if let previous, previous.isLowercase, character.isUppercase, !current.isEmpty {
                    words.append(current)
                    current = ""
                }
                current.append(character)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
            previous = character
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    static func slugify(_ text: String) -> String {
        words(text).map { $0.lowercased() }.joined(separator: "-")
    }

    static func snakeCase(_ text: String) -> String {
        words(text).map { $0.lowercased() }.joined(separator: "_")
    }

    static func camelCase(_ text: String) -> String {
        let parts = words(text).map { $0.lowercased() }
        guard let first = parts.first else { return "" }
        return first + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }

    static func stripHTML(_ html: String) -> String {
        var text = html
        for pattern in ["(?is)<(script|style)[^>]*>.*?</\\1>", "(?s)<!--.*?-->"] {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>|</(p|div|li|tr|h[1-6])>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = htmlEntityDecode(text).replacingOccurrences(of: "\u{00A0}", with: " ")
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = lines(text).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func markdownLink(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil, !trimmed.contains(" ") else { return nil }
        return "[\(trimmed)](\(trimmed))"
    }

    static func extractURLs(_ text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let urls = detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { $0.url }
            .filter { $0.scheme != "mailto" }.map(\.absoluteString)
        return urls.isEmpty ? nil : urls.joined(separator: "\n")
    }

    static func extractEmailAddresses(_ text: String) -> String? {
        let pattern = try! NSRegularExpression(pattern: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}")
        let source = text as NSString
        let found = pattern.matches(in: text, range: NSRange(location: 0, length: source.length)).map { source.substring(with: $0.range) }
        return found.isEmpty ? nil : found.joined(separator: "\n")
    }

    static func createList(_ text: String) -> String {
        let items = lines(text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { "  <li>\($0.trimmingCharacters(in: .whitespaces))</li>" }
        return (["<ul>"] + items + ["</ul>"]).joined(separator: "\n")
    }

    /// The text of a stored clip without formatting: its plain text type, else text from its rich text or HTML,
    /// else its file paths. Nil when the clip has no text (an image, for example).
    static func plainText(of items: [[Representation]]) -> String? {
        let stringType = NSPasteboard.PasteboardType.string.rawValue
        var texts: [String] = []
        for item in items {
            if let data = item.first(where: { $0.type == stringType })?.data, let text = String(data: data, encoding: .utf8) {
                texts.append(text)
            } else if let data = item.first(where: { $0.type == NSPasteboard.PasteboardType.rtf.rawValue })?.data,
                      let attributed = NSAttributedString(rtf: data, documentAttributes: nil) {
                texts.append(attributed.string)
            } else if let data = item.first(where: { $0.type == NSPasteboard.PasteboardType.html.rawValue })?.data,
                      let html = String(data: data, encoding: .utf8) {
                texts.append(stripHTML(html))
            } else if let data = item.first(where: { $0.type == NSPasteboard.PasteboardType.fileURL.rawValue })?.data,
                      let text = String(data: data, encoding: .utf8), let url = URL(string: text) {
                texts.append(url.path)
            }
        }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }
}
