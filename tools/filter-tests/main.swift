// Text filter, plain text extraction and recall format checks. Run: bash tools/run-tests.sh
import AppKit
@testable import SimpleClipboardHistoryKit

var checks = 0
var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    checks += 1
    if !condition() { failures += 1; print("FAIL: \(label)") }
}
func apply(_ id: String, _ text: String) -> String? {
    guard let filter = TextFilter.named(id) else { print("FAIL: no filter \(id)"); failures += 1; return nil }
    return filter.apply(text)
}

// MARK: the filter list
check(Set(TextFilter.all.map(\.id)).count == TextFilter.all.count, "filter ids are unique")
check(TextFilter.all.allSatisfy { !$0.name.isEmpty && !$0.summary.isEmpty }, "every filter has a name and summary")
check(TextFilter.Group.allCases.allSatisfy { group in TextFilter.all.contains { $0.group == group } }, "every group has filters")
check(TextFilter.matching("").count == TextFilter.all.count, "empty query matches all")
check(TextFilter.matching("CASE").map(\.id).contains("snake-case"), "query matches names, any case")
check(TextFilter.matching("developer").allSatisfy { $0.group == .developer }, "query matches group names")
let allText = TextFilter.all.flatMap { [$0.name, $0.summary] }.joined()
check(!allText.contains("\u{2014}") && !allText.contains("\u{2013}"), "no em or en dashes in filter text")

// MARK: Text & Writing
check(apply("plain-text", "a\nb") == "a\nb", "plain text keeps the text")
check(apply("single-line", "  123 Main St\n\n Springfield,\r\nIL ") == "123 Main St Springfield, IL", "single line")
check(apply("trim-whitespace", "  a b \t\n\tc  ") == "a b\nc", "trim each line")
check(apply("normalize-whitespace", " a   b \n\n\t c\td ") == "a b\nc d", "normalize whitespace")
check(apply("uppercase", "abc é") == "ABC É", "uppercase")
check(apply("lowercase", "ABC É") == "abc é", "lowercase")
check(apply("titlecase", "hello wORLD, foo-bar 2nd") == "Hello WORLD, Foo-Bar 2nd", "titlecase keeps the rest of each word")
check(apply("straight-punctuation", "\u{201C}it\u{2019}s\u{201D} \u{2014} wait\u{2026}") == "\"it's\" -- wait...", "straight punctuation")
check(apply("sort-lines", "b\nA\nc\n") == "A\nb\nc\n", "sort lines, any case, trailing newline kept")
check(apply("remove-duplicate-lines", "a\nb\na\nc\nb") == "a\nb\nc", "remove duplicate lines")
check(apply("remove-list-numbering", "1. one\n  2) two\n3 three\n10. ten") == "one\ntwo\n3 three\nten", "remove list numbering")

// MARK: Developer
check(apply("url-encode", "a b&c=d/é") == "a%20b%26c%3Dd%2F%C3%A9", "url encode")
check(apply("url-decode", "a%20b%26c") == "a b&c", "url decode")
check(apply("url-decode", "%zz") == nil, "invalid percent-encoding does not apply")
check(apply("base64-encode", "hello") == "aGVsbG8=", "base64 encode")
check(apply("base64-decode", "aGVs\nbG8") == "hello", "base64 decode ignores line breaks and missing padding")
check(apply("base64-decode", "not base64!") == nil, "invalid base64 does not apply")
check(apply("hex-encode", "Hi") == "4869", "hex encode")
check(apply("hex-decode", "0x48 69") == "Hi", "hex decode")
check(apply("hex-decode", "486") == nil && apply("hex-decode", "zz") == nil, "invalid hex does not apply")
check(apply("html-entity-encode", "<a href=\"x\">Tom & 'Jerry'</a>") == "&lt;a href=&quot;x&quot;&gt;Tom &amp; &#39;Jerry&#39;&lt;/a&gt;",
      "html entity encode")
check(apply("html-entity-decode", "a &amp; b &lt;c&gt; &#8212; &#x41; &unknown; &mdash;") == "a & b <c> \u{2014} A &unknown; \u{2014}",
      "html entity decode, unknown names kept")
check(apply("json-string-escape", "say \"hi\"\n\tback\\slash\u{1}") == "say \\\"hi\\\"\\n\\tback\\\\slash\\u0001", "json string escape")
check(apply("format-json", "{\"b\":1,\"a\":[1,2],\"url\":\"http://x/y\"}") == "{\n  \"a\" : [\n    1,\n    2\n  ],\n  \"b\" : 1,\n  \"url\" : \"http://x/y\"\n}",
      "format json with sorted keys and unescaped slashes")
check(apply("format-json", "{oops") == nil, "invalid json does not apply")
check(apply("slugify", "Héllo, World! It's 2026") == "hello-world-it-s-2026", "slugify")
check(apply("snake-case", "Hello World fooBar") == "hello_world_foo_bar", "snake case")
check(apply("camel-case", "hello world-foo_bar") == "helloWorldFooBar", "camel case")
check(apply("camel-case", "!!!") == "", "camel case of no words")

// MARK: Web & Markdown
check(apply("strip-html", "<style>p{}</style><p>One &amp; two</p><p>three<br>four</p><script>x()</script>") == "One & two\nthree\nfour",
      "strip html")
check(apply("markdown-link", " https://example.com/a \n") == "[https://example.com/a](https://example.com/a)", "markdown link")
check(apply("markdown-link", "not a url") == nil, "markdown link needs a URL")
check(apply("markdown-blockquote", "a\nb") == "> a\n> b", "markdown blockquote")
check(apply("extract-urls", "see https://a.com/x and http://b.org, mail me@c.com") == "https://a.com/x\nhttp://b.org", "extract urls")
check(apply("extract-urls", "nothing here") == nil, "no urls does not apply")
check(apply("extract-email-addresses", "to: a.b@c.com, x@y.co.uk; bad@x") == "a.b@c.com\nx@y.co.uk", "extract email addresses")
check(apply("create-list", "one\n\n two ") == "<ul>\n  <li>one</li>\n  <li>two</li>\n</ul>", "create list")
check(apply("paragraph-tags", "x") == "<p>x</p>", "paragraph tags")

// MARK: plain text extraction
let stringType = NSPasteboard.PasteboardType.string.rawValue
let rtf = NSAttributedString(string: "bold text", attributes: [.font: NSFont.boldSystemFont(ofSize: 12)])
let rtfData = rtf.rtf(from: NSRange(location: 0, length: rtf.length), documentAttributes: [:])!
let rich: [[Representation]] = [[Representation(type: stringType, data: Data("bold text".utf8)),
                                 Representation(type: NSPasteboard.PasteboardType.rtf.rawValue, data: rtfData)]]
check(TextTransforms.plainText(of: rich) == "bold text", "plain text from the text type")
check(TextTransforms.plainText(of: [[Representation(type: NSPasteboard.PasteboardType.rtf.rawValue, data: rtfData)]]) == "bold text",
      "plain text from rich text alone")
check(TextTransforms.plainText(of: [[Representation(type: NSPasteboard.PasteboardType.html.rawValue, data: Data("<b>x</b> &amp; y".utf8))]])
      == "x & y", "plain text from html alone")
check(TextTransforms.plainText(of: [[Representation(type: NSPasteboard.PasteboardType.fileURL.rawValue, data: Data("file:///tmp/a%20b".utf8))]])
      == "/tmp/a b", "plain text of a file is its path")
let image: [[Representation]] = [[Representation(type: NSPasteboard.PasteboardType.png.rawValue, data: Data([1, 2]))]]
check(TextTransforms.plainText(of: image) == nil, "image has no plain text")
check(TextTransforms.plainText(of: [[Representation(type: stringType, data: Data("a".utf8))],
                                    [Representation(type: stringType, data: Data("b".utf8))]]) == "a\nb", "several items join with line breaks")

// MARK: recall formats
let plainOnly = [[Representation(type: stringType, data: Data("bold text".utf8))]]
check(Recall.items(for: rich, format: .original) == rich, "original keeps every type")
check(Recall.items(for: rich, format: .plainText) == plainOnly, "plain text keeps only the text")
check(Recall.items(for: image, format: .plainText) == image, "plain text of an image keeps the image")
check(Recall.items(for: rich, format: .filter("uppercase")) == [[Representation(type: stringType, data: Data("BOLD TEXT".utf8))]],
      "filter writes its result as text")
check(Recall.items(for: image, format: .filter("uppercase")) == nil, "filter on an image does not apply")
check(Recall.items(for: rich, format: .filter("base64-decode")) == nil, "filter that does not apply returns nil")
check(Recall.items(for: rich, format: .filter("no-such-filter")) == nil, "unknown filter returns nil")
let pasteboard = NSPasteboard(name: NSPasteboard.Name("simple-clipboard-history-filter-tests-\(UUID().uuidString)"))
check(Recall.perform(items: rich, mode: .clipboard, format: .plainText, pasteboard: pasteboard) == .onClipboard, "plain recall outcome")
check(pasteboard.pasteboardItems?.count == 1 && pasteboard.pasteboardItems?.first?.types == [.string]
      && pasteboard.string(forType: .string) == "bold text", "pasteboard holds only plain text")
pasteboard.clearContents()
pasteboard.setString("unchanged", forType: .string)
check(Recall.perform(items: rich, mode: .clipboard, format: .filter("base64-decode"), pasteboard: pasteboard) == .filterFailed,
      "failed filter outcome")
check(pasteboard.string(forType: .string) == "unchanged", "failed filter leaves the pasteboard alone")
pasteboard.releaseGlobally()

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
