import Foundation

/// A key the picker understands, already translated from the key event.
enum PickerKey: Equatable {
    case up, down, pageUp, pageDown, home, end
    case enter, escape, tab
    case deleteBackward
    case deleteWordBackward
    case clearQuery
    /// Cmd-1 to Cmd-9: recall the visible row with this number.
    case recallNumber(Int)
    case text(String)
}

enum PickerAction: Equatable {
    case none
    case close
    case recall(Int64)
}

/// The picker's state and key handling, without any drawing, so it can be tested without a window.
/// Rows come from the store's search: most recently copied first, filtered by the query.
final class PickerModel {
    static let resultLimit = 500

    private let search: (String, Int) -> [ClipSummary]
    private(set) var query = ""
    private(set) var rows: [ClipSummary] = []
    private(set) var selectedIndex: Int?
    /// The first row on screen. Cmd-1 recalls this row.
    private(set) var firstRow = 0
    private(set) var previewOpen = false
    /// Set by the view from its height.
    var visibleRowCount = 10 {
        didSet { visibleRowCount = max(1, visibleRowCount); scrollToSelection() }
    }

    init(search: @escaping (String, Int) -> [ClipSummary]) {
        self.search = search
    }

    var selectedClip: ClipSummary? { selectedIndex.map { rows[$0] } }

    /// Clears the query and loads the newest clips. Called each time the picker opens.
    func reset() {
        query = ""
        previewOpen = false
        reload()
    }

    func reload() {
        rows = search(query, Self.resultLimit)
        firstRow = 0
        selectedIndex = rows.isEmpty ? nil : 0
    }

    func select(_ index: Int) {
        guard !rows.isEmpty else { return }
        selectedIndex = min(max(0, index), rows.count - 1)
        scrollToSelection()
    }

    /// Scrolls by whole rows, for the scroll wheel. The selection stays where it is.
    func scroll(by rowCount: Int) {
        firstRow = min(max(0, firstRow + rowCount), max(0, rows.count - visibleRowCount))
    }

    private func scrollToSelection() {
        guard let selected = selectedIndex else { firstRow = 0; return }
        if selected < firstRow { firstRow = selected }
        if selected >= firstRow + visibleRowCount { firstRow = selected - visibleRowCount + 1 }
    }

    func handle(_ key: PickerKey) -> PickerAction {
        let current = selectedIndex ?? 0
        switch key {
        case .up: select(current - 1)
        case .down: select(current + 1)
        case .pageUp: select(current - visibleRowCount)
        case .pageDown: select(current + visibleRowCount)
        case .home: select(0)
        case .end: select(rows.count - 1)
        case .escape:
            if previewOpen { previewOpen = false; return .none }
            return .close
        case .tab:
            if selectedIndex != nil || previewOpen { previewOpen.toggle() }
        case .enter:
            return selectedClip.map { .recall($0.id) } ?? .none
        case .recallNumber(let number):
            let index = firstRow + number - 1
            guard number >= 1, number <= 9, index < rows.count, index < firstRow + visibleRowCount else { return .none }
            return .recall(rows[index].id)
        case .deleteBackward:
            guard !query.isEmpty else { return .none }
            setQuery(String(query.dropLast()))
        case .deleteWordBackward:
            var text = Substring(query)
            while text.last?.isWhitespace == true { text = text.dropLast() }
            while let last = text.last, !last.isWhitespace { text = text.dropLast() }
            setQuery(String(text))
        case .clearQuery:
            setQuery("")
        case .text(let characters):
            let printable = characters.filter { !$0.isNewline && !($0.unicodeScalars.first.map { CharacterSet.controlCharacters.contains($0) } ?? false) }
            guard !printable.isEmpty else { return .none }
            setQuery(query + printable)
        }
        return .none
    }

    private func setQuery(_ text: String) {
        guard text != query else { return }
        query = text
        reload()
    }
}
