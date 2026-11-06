// Copied from noteapp (github.com/evadnoob/noteapp) Sources/NoteApp/KDL.swift at 617d7221eb0cc984ad1605673f5746e50295b668.
// Keep changes in step with noteapp until both apps share a package.
import Foundation

// A small KDL 2.0.0 reader and writer (https://kdl.dev/spec). It covers what a settings file needs: nodes,
// arguments, properties, children, quoted, raw, multi-line and bare strings, numbers, keywords, comments,
// slashdash and line continuations. Type annotations are parsed and ignored.
//
// One extension, off by default: with `hashComments: true`, a `#` followed by a space, a tab, a line break or the
// end of the file starts a comment that runs to the end of the line (like shell, tmux and kitty files). In real KDL
// a `#` is always followed by a letter (#true) or by " or # (raw strings), so this cannot be confused with KDL syntax.
// A file that uses it is not valid KDL for other tools.

enum KDLValue: Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
}

struct KDLNode {
    var name: String
    var arguments: [KDLValue] = []
    var properties: [(key: String, value: KDLValue)] = []
    var children: [KDLNode] = []
    var line = 1
}

struct KDLError: Error, CustomStringConvertible {
    let line: Int
    let column: Int
    let message: String
    var description: String { "line \(line), column \(column): \(message)" }
}

enum KDL {
    static func parse(_ text: String, hashComments: Bool = false) throws -> [KDLNode] {
        var parser = KDLParser(text, hashComments: hashComments)
        return try parser.parseNodes(topLevel: true)
    }

    static func serialize(_ nodes: [KDLNode], indent: Int = 0) -> String {
        let pad = String(repeating: "    ", count: indent)
        var output = ""
        for node in nodes {
            var line = pad + name(node.name)
            for argument in node.arguments { line += " " + value(argument) }
            for property in node.properties { line += " " + name(property.key) + "=" + value(property.value) }
            if node.children.isEmpty {
                output += line + "\n"
            } else {
                output += line + " {\n" + serialize(node.children, indent: indent + 1) + pad + "}\n"
            }
        }
        return output
    }

    static func value(_ value: KDLValue) -> String {
        switch value {
        case .string(let text): return quote(text)
        case .bool(let flag): return flag ? "#true" : "#false"
        case .null: return "#null"
        case .number(let number):
            if number.isNaN { return "#nan" }
            if number.isInfinite { return number < 0 ? "#-inf" : "#inf" }
            if number == number.rounded() && abs(number) < 1e15 { return String(Int64(number)) }
            return String(describing: number)
        }
    }

    private static func name(_ text: String) -> String {
        KDLParser.isPlainIdentifier(text) ? text : quote(text)
    }

    static func quote(_ text: String) -> String {
        var output = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    output += "\\u{" + String(scalar.value, radix: 16) + "}"
                } else {
                    output.unicodeScalars.append(scalar)
                }
            }
        }
        return output + "\""
    }
}

private struct KDLParser {
    private let s: [Unicode.Scalar]
    private let hashComments: Bool
    private var i = 0

    init(_ text: String, hashComments: Bool) {
        s = Array(text.unicodeScalars)
        self.hashComments = hashComments
    }

    /// True at a `#` that starts a comment (only when the hashComments extension is on).
    private func isHashComment() -> Bool {
        guard hashComments, peek() == "#" else { return false }
        guard let next = peek(1) else { return true }
        return KDLParser.isSpace(next) || KDLParser.isNewline(next)
    }

    // MARK: character classes

    private static let forbiddenInIdentifier: Set<Unicode.Scalar> = ["\\", "/", "(", ")", "{", "}", ";", "[", "]", "\"", "#", "="]

    private static func isNewline(_ c: Unicode.Scalar) -> Bool {
        c == "\n" || c == "\r" || c == "\u{85}" || c == "\u{0B}" || c == "\u{0C}" || c == "\u{2028}" || c == "\u{2029}"
    }

    private static func isSpace(_ c: Unicode.Scalar) -> Bool {
        switch c.value {
        case 0x20, 0x09, 0xA0, 0x1680, 0x202F, 0x205F, 0x3000, 0xFEFF: return true
        case 0x2000...0x200A: return true
        default: return false
        }
    }

    private static func isIdentifierScalar(_ c: Unicode.Scalar) -> Bool {
        !isSpace(c) && !isNewline(c) && !forbiddenInIdentifier.contains(c) && c.value > 0x20 && c.value != 0x7F
    }

    private static func isDigit(_ c: Unicode.Scalar?) -> Bool {
        guard let c = c else { return false }
        return c.value >= 0x30 && c.value <= 0x39
    }

    /// True if the text can be written as a bare identifier (so it needs no quotes).
    static func isPlainIdentifier(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars)
        guard let first = scalars.first, scalars.allSatisfy(isIdentifierScalar) else { return false }
        if isDigit(first) { return false }
        if (first == "+" || first == "-" || first == ".") {
            if scalars.count > 1 && (isDigit(scalars[1]) || (scalars[1] == "." && scalars.count > 2 && isDigit(scalars[2]))) { return false }
        }
        return !["true", "false", "null", "inf", "-inf", "nan"].contains(text)
    }

    // MARK: positions and errors

    private func peek(_ offset: Int = 0) -> Unicode.Scalar? {
        let j = i + offset
        return j < s.count ? s[j] : nil
    }

    private mutating func advance(_ count: Int = 1) { i += count }

    private func lineNumber(at index: Int) -> Int {
        var line = 1
        var j = 0
        while j < index && j < s.count {
            let c = s[j]
            if c == "\r" {
                if !(j + 1 < s.count && s[j + 1] == "\n") { line += 1 }
            } else if KDLParser.isNewline(c) {
                line += 1
            }
            j += 1
        }
        return line
    }

    private func error(_ message: String, at index: Int? = nil) -> KDLError {
        let position = min(index ?? i, s.count)
        var column = 1
        var j = position
        while j > 0 && !KDLParser.isNewline(s[j - 1]) { column += 1; j -= 1 }
        return KDLError(line: lineNumber(at: position), column: column, message: message)
    }

    // MARK: whitespace and comments

    private mutating func skipLineComment() {
        while let c = peek(), !KDLParser.isNewline(c) { advance() }
    }

    private mutating func skipBlockComment() throws {
        let start = i
        advance(2)
        var depth = 1
        while depth > 0 {
            guard let c = peek() else { throw error("unterminated /* comment", at: start) }
            if c == "/" && peek(1) == "*" { depth += 1; advance(2) }
            else if c == "*" && peek(1) == "/" { depth -= 1; advance(2) }
            else { advance() }
        }
    }

    private mutating func skipNewline() {
        if peek() == "\r" && peek(1) == "\n" { advance(2) } else { advance() }
    }

    /// Spaces, block comments and `\` line continuations, within one node. Returns true if anything was skipped.
    private mutating func skipInlineSpace() throws -> Bool {
        var skipped = false
        while let c = peek() {
            if KDLParser.isSpace(c) {
                advance()
            } else if c == "/" && peek(1) == "*" {
                try skipBlockComment()
            } else if c == "\\" {
                advance()
                while let d = peek(), KDLParser.isSpace(d) { advance() }
                if peek() == "/" && peek(1) == "/" { skipLineComment() }
                guard let d = peek(), KDLParser.isNewline(d) else { throw error("expected a newline after \\") }
                skipNewline()
            } else {
                break
            }
            skipped = true
        }
        return skipped
    }

    /// Everything that may sit between nodes: spaces, newlines, semicolons and comments.
    private mutating func skipLineSpace() throws {
        while let c = peek() {
            if KDLParser.isSpace(c) || KDLParser.isNewline(c) || c == ";" {
                advance()
            } else if c == "/" && peek(1) == "/" {
                skipLineComment()
            } else if isHashComment() {
                skipLineComment()
            } else if c == "/" && peek(1) == "*" {
                try skipBlockComment()
            } else {
                break
            }
        }
    }

    // MARK: nodes

    mutating func parseNodes(topLevel: Bool) throws -> [KDLNode] {
        var nodes: [KDLNode] = []
        while true {
            try skipLineSpace()
            guard let c = peek() else {
                if topLevel { return nodes }
                throw error("missing closing }")
            }
            if c == "}" {
                if topLevel { throw error("unexpected }") }
                return nodes
            }
            var discard = false
            if c == "/" && peek(1) == "-" {
                advance(2)
                try skipLineSpace()
                discard = true
            }
            let node = try parseNode()
            if !discard { nodes.append(node) }
        }
    }

    private enum Entry {
        case argument(KDLValue)
        case property(String, KDLValue)
    }

    private mutating func parseNode() throws -> KDLNode {
        let start = i
        try skipTypeAnnotation()
        var node = KDLNode(name: try parseName())
        node.line = lineNumber(at: start)
        var sawChildren = false

        while true {
            let separated = try skipInlineSpace()
            guard let c = peek() else { break }
            if KDLParser.isNewline(c) || c == ";" || c == "}" { break }
            if c == "/" && peek(1) == "/" { skipLineComment(); break }
            if isHashComment() { skipLineComment(); break }
            if !separated && c != "{" { throw error("expected a space before this") }

            var discard = false
            if c == "/" && peek(1) == "-" {
                advance(2)
                try skipLineSpace()
                discard = true
            }
            guard let d = peek() else { throw error("unexpected end of file after /-") }

            if d == "{" {
                if sawChildren && !discard { throw error("a node can have only one children block") }
                advance()
                let children = try parseNodes(topLevel: false)
                guard peek() == "}" else { throw error("missing closing }") }
                advance()
                if !discard { node.children = children; sawChildren = true }
                continue
            }
            if sawChildren && !discard { throw error("arguments and properties must come before the children block") }
            let entry = try parseEntry()
            if discard { continue }
            switch entry {
            case .argument(let value): node.arguments.append(value)
            case .property(let key, let value): node.properties.append((key, value))
            }
        }
        return node
    }

    private mutating func skipTypeAnnotation() throws {
        guard peek() == "(" else { return }
        let start = i
        advance()
        _ = try skipInlineSpace()
        _ = try parseStringToken()
        _ = try skipInlineSpace()
        guard peek() == ")" else { throw error("unterminated type annotation", at: start) }
        advance()
    }

    private mutating func parseName() throws -> String {
        guard let c = peek() else { throw error("expected a node name") }
        if c == "\"" || c == "#" {
            guard let text = try parseStringToken() else { throw error("expected a node name") }
            return text
        }
        return try parseBareIdentifier()
    }

    private mutating func parseEntry() throws -> Entry {
        try skipTypeAnnotation()
        let start = i
        let token = try parseValueToken()
        if case .string(let key) = token.value, token.isString {
            // A string followed by = is a property key.
            let saved = i
            _ = try skipInlineSpace()
            if peek() == "=" {
                advance()
                _ = try skipInlineSpace()
                try skipTypeAnnotation()
                let valueToken = try parseValueToken()
                return .property(key, valueToken.value)
            }
            i = saved
        }
        _ = start
        return .argument(token.value)
    }

    // MARK: values

    private struct Token {
        var value: KDLValue
        var isString: Bool
    }

    private mutating func parseValueToken() throws -> Token {
        guard let c = peek() else { throw error("expected a value") }
        if c == "\"" || (c == "#" && (peek(1) == "\"" || peek(1) == "#")) {
            guard let text = try parseStringToken() else { throw error("expected a string") }
            return Token(value: .string(text), isString: true)
        }
        if c == "#" {
            let start = i
            advance()
            var word = ""
            while let d = peek(), KDLParser.isIdentifierScalar(d) { word.unicodeScalars.append(d); advance() }
            switch word {
            case "true": return Token(value: .bool(true), isString: false)
            case "false": return Token(value: .bool(false), isString: false)
            case "null": return Token(value: .null, isString: false)
            case "inf": return Token(value: .number(.infinity), isString: false)
            case "-inf": return Token(value: .number(-.infinity), isString: false)
            case "nan": return Token(value: .number(.nan), isString: false)
            default: throw error("unknown keyword #\(word)", at: start)
            }
        }
        if looksLikeNumber() {
            let start = i
            var word = ""
            while let d = peek(), KDLParser.isIdentifierScalar(d) { word.unicodeScalars.append(d); advance() }
            guard let number = KDLParser.number(word) else { throw error("invalid number \(word)", at: start) }
            return Token(value: .number(number), isString: false)
        }
        let start = i
        let word = try parseBareIdentifier()
        if ["true", "false", "null", "inf", "-inf", "nan"].contains(word) {
            throw error("write #\(word) for the keyword, or quote the string", at: start)
        }
        return Token(value: .string(word), isString: true)
    }

    private func looksLikeNumber() -> Bool {
        guard let c = peek() else { return false }
        if KDLParser.isDigit(c) { return true }
        if c == "+" || c == "-" {
            if KDLParser.isDigit(peek(1)) { return true }
            return peek(1) == "." && KDLParser.isDigit(peek(2))
        }
        return c == "." && KDLParser.isDigit(peek(1))
    }

    private static func number(_ text: String) -> Double? {
        var t = text.replacingOccurrences(of: "_", with: "")
        var sign = 1.0
        if t.hasPrefix("+") { t.removeFirst() } else if t.hasPrefix("-") { sign = -1; t.removeFirst() }
        for (prefix, radix) in [("0x", 16), ("0o", 8), ("0b", 2)] where t.hasPrefix(prefix) {
            guard let value = Int(t.dropFirst(2), radix: radix) else { return nil }
            return sign * Double(value)
        }
        guard let first = t.unicodeScalars.first, isDigit(first) || first == "." else { return nil }
        return Double(t).map { sign * $0 }
    }

    private mutating func parseBareIdentifier() throws -> String {
        let start = i
        var word = ""
        while let c = peek(), KDLParser.isIdentifierScalar(c) { word.unicodeScalars.append(c); advance() }
        guard !word.isEmpty else {
            if let c = peek() { throw error("unexpected \"\(Character(c))\"", at: start) }
            throw error("unexpected end of file", at: start)
        }
        return word
    }

    // MARK: strings

    /// Parses a quoted or raw string. Returns nil if the next character does not start one.
    private mutating func parseStringToken() throws -> String? {
        guard let c = peek() else { return nil }
        if c == "\"" { return try parseQuoted() }
        if c == "#" { return try parseRaw() }
        return try parseBareIdentifier()
    }

    private mutating func parseQuoted() throws -> String {
        let start = i
        if peek(1) == "\"" && peek(2) == "\"" {
            advance(3)
            try consumeNewlineAfterOpening(at: start)
            var raw: [Unicode.Scalar] = []
            while true {
                guard let c = peek() else { throw error("unterminated multi-line string", at: start) }
                if c == "\\" {
                    raw.append(c)
                    advance()
                    if let d = peek() { raw.append(d); advance() }
                } else if c == "\"" && peek(1) == "\"" && peek(2) == "\"" {
                    advance(3)
                    break
                } else {
                    raw.append(c)
                    advance()
                }
            }
            return try unescape(dedent(raw, at: start), at: start)
        }
        advance()
        var raw: [Unicode.Scalar] = []
        while true {
            guard let c = peek() else { throw error("unterminated string", at: start) }
            if KDLParser.isNewline(c) { throw error("a string cannot contain a newline (use \"\"\" for multi-line)", at: start) }
            if c == "\\" {
                raw.append(c)
                advance()
                if let d = peek() { raw.append(d); advance() }
            } else if c == "\"" {
                advance()
                break
            } else {
                raw.append(c)
                advance()
            }
        }
        return try unescape(raw, at: start)
    }

    private mutating func parseRaw() throws -> String {
        let start = i
        var hashes = 0
        while peek() == "#" { hashes += 1; advance() }
        guard peek() == "\"" else {
            if hashes == 1, peek() == nil || KDLParser.isSpace(peek()!) || KDLParser.isNewline(peek()!) {
                throw error("# does not start a comment in KDL (use //)", at: start)
            }
            throw error("expected \" after #", at: start)
        }
        let multiline = peek(1) == "\"" && peek(2) == "\""
        advance(multiline ? 3 : 1)
        if multiline { try consumeNewlineAfterOpening(at: start) }
        var raw: [Unicode.Scalar] = []
        while true {
            guard let c = peek() else { throw error("unterminated raw string", at: start) }
            if c == "\"" {
                let quotes = multiline ? 3 : 1
                var matches = true
                for k in 1..<quotes where peek(k) != "\"" { matches = false }
                for k in 0..<hashes where peek(quotes + k) != "#" { matches = false }
                if matches {
                    advance(quotes + hashes)
                    break
                }
            }
            if !multiline && KDLParser.isNewline(c) { throw error("a raw string cannot contain a newline (use #\"\"\")", at: start) }
            raw.append(c)
            advance()
        }
        return multiline ? try dedentToString(raw, at: start) : String(String.UnicodeScalarView(raw))
    }

    private mutating func consumeNewlineAfterOpening(at start: Int) throws {
        // Spaces may follow the opening quotes, but then a newline is required.
        while let c = peek(), KDLParser.isSpace(c) { advance() }
        guard let c = peek(), KDLParser.isNewline(c) else {
            throw error("a multi-line string must start on a new line after the opening quotes", at: start)
        }
        skipNewline()
    }

    private func dedentToString(_ raw: [Unicode.Scalar], at start: Int) throws -> String {
        String(String.UnicodeScalarView(try dedent(raw, at: start)))
    }

    /// Removes the indentation of the closing quotes from every line, and the final line break.
    private func dedent(_ raw: [Unicode.Scalar], at start: Int) throws -> [Unicode.Scalar] {
        let text = String(String.UnicodeScalarView(raw)).replacingOccurrences(of: "\r\n", with: "\n")
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let last = lines.popLast(), last.allSatisfy({ $0 == " " || $0 == "\t" }) else {
            throw error("the closing quotes of a multi-line string must be on their own line", at: start)
        }
        var result: [String] = []
        for line in lines {
            if line.allSatisfy({ $0 == " " || $0 == "\t" }) { result.append(""); continue }
            guard line.hasPrefix(last) else {
                throw error("a line in a multi-line string is indented less than the closing quotes", at: start)
            }
            result.append(String(line.dropFirst(last.count)))
        }
        return Array(result.joined(separator: "\n").unicodeScalars)
    }

    private func unescape(_ raw: [Unicode.Scalar], at start: Int) throws -> String {
        var output = String.UnicodeScalarView()
        var j = 0
        while j < raw.count {
            let c = raw[j]
            guard c == "\\" else { output.append(c); j += 1; continue }
            j += 1
            guard j < raw.count else { throw error("a string cannot end with a backslash", at: start) }
            let e = raw[j]
            j += 1
            switch e {
            case "n": output.append("\n")
            case "r": output.append("\r")
            case "t": output.append("\t")
            case "\\": output.append("\\")
            case "\"": output.append("\"")
            case "b": output.append("\u{08}")
            case "f": output.append("\u{0C}")
            case "s": output.append(" ")
            case "u":
                guard j < raw.count, raw[j] == "{" else { throw error("expected { after \\u", at: start) }
                var hex = ""
                j += 1
                while j < raw.count, raw[j] != "}" { hex.unicodeScalars.append(raw[j]); j += 1 }
                guard j < raw.count, let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) else {
                    throw error("invalid \\u{...} escape", at: start)
                }
                j += 1
                output.append(scalar)
            default:
                if KDLParser.isSpace(e) || KDLParser.isNewline(e) {
                    // A backslash before whitespace removes all whitespace up to the next character.
                    while j < raw.count, KDLParser.isSpace(raw[j]) || KDLParser.isNewline(raw[j]) { j += 1 }
                } else {
                    throw error("unknown escape \\\(Character(e))", at: start)
                }
            }
        }
        return String(output)
    }
}
