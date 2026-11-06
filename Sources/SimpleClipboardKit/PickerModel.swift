import Foundation

/// A key the picker understands, already translated from the key event.
enum PickerKey: Equatable {
    case up, down, pageUp, pageDown, home, end
    /// Return: recall with the default format.
    case enter
    /// Shift-Return: recall with the other format (plain text or formatted).
    case enterAlternate
    /// Command-Return: choose a filter for the selected clip.
    case enterFilter
    case escape, tab
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
    case recall(Int64, RecallFormat)
}

/// A row of the filter step: a group heading or a filter.
enum FilterRow: Equatable {
    case heading(TextFilter.Group)
    case filter(TextFilter)
}

/// The picker's state and key handling, without any drawing, so it can be tested without a window.
/// The clip step lists clips, most recently copied first, filtered by the query. The filter step lists the
/// filters for one clip, under their group headings.
final class PickerModel {
    enum Step: Equatable {
        case clips
        case filters(clipID: Int64)
    }

    static let resultLimit = 500

    private let search: (String, Int) -> [ClipSummary]
    private(set) var step = Step.clips
    private(set) var query = ""
    private(set) var rows: [ClipSummary] = []
    private(set) var selectedIndex: Int?
    /// The first row on screen. Cmd-1 recalls this row.
    private(set) var firstRow = 0
    private(set) var previewOpen = false
    /// Return pastes plain text and Shift-Return formatted text when this is on; the other way round when off.
    var alwaysPastePlainText = false

    private(set) var filterQuery = ""
    private(set) var filterRows: [FilterRow] = []
    private(set) var selectedFilterIndex: Int?
    private(set) var firstFilterRow = 0
    /// The clip step's query and selection, restored when the filter step closes.
    private var savedClipState: (query: String, selected: Int?, first: Int)?

    /// Set by the view from its height.
    var visibleRowCount = 10 {
        didSet { visibleRowCount = max(1, visibleRowCount); scrollToSelection() }
    }

    init(search: @escaping (String, Int) -> [ClipSummary]) {
        self.search = search
    }

    var selectedClip: ClipSummary? { selectedIndex.map { rows[$0] } }

    var selectedFilter: TextFilter? {
        guard let index = selectedFilterIndex, case .filter(let filter) = filterRows[index] else { return nil }
        return filter
    }

    var defaultFormat: RecallFormat { alwaysPastePlainText ? .plainText : .original }
    var alternateFormat: RecallFormat { alwaysPastePlainText ? .original : .plainText }

    /// Clears the query and loads the newest clips. Called each time the picker opens.
    func reset() {
        step = .clips
        query = ""
        previewOpen = false
        reload()
    }

    func reload() {
        rows = search(query, Self.resultLimit)
        firstRow = 0
        selectedIndex = rows.isEmpty ? nil : 0
    }

    // MARK: selection

    /// Selects a clip row, or in the filter step a filter row (headings are skipped).
    func select(_ index: Int) {
        switch step {
        case .clips:
            guard !rows.isEmpty else { return }
            selectedIndex = min(max(0, index), rows.count - 1)
        case .filters:
            selectFilter(near: index, direction: 1)
        }
        scrollToSelection()
    }

    /// Scrolls by whole rows, for the scroll wheel. The selection stays where it is.
    func scroll(by rowCount: Int) {
        switch step {
        case .clips: firstRow = min(max(0, firstRow + rowCount), max(0, rows.count - visibleRowCount))
        case .filters: firstFilterRow = min(max(0, firstFilterRow + rowCount), max(0, filterRows.count - visibleRowCount))
        }
    }

    private func scrollToSelection() {
        switch step {
        case .clips:
            guard let selected = selectedIndex else { firstRow = 0; return }
            if selected < firstRow { firstRow = selected }
            if selected >= firstRow + visibleRowCount { firstRow = selected - visibleRowCount + 1 }
        case .filters:
            guard let selected = selectedFilterIndex else { firstFilterRow = 0; return }
            // Keep the heading above the first filter of a group in view.
            var top = selected
            if selected > 0, case .heading = filterRows[selected - 1] { top = selected - 1 }
            if top < firstFilterRow { firstFilterRow = top }
            if selected >= firstFilterRow + visibleRowCount { firstFilterRow = selected - visibleRowCount + 1 }
        }
    }

    private var filterIndices: [Int] {
        filterRows.indices.filter { if case .filter = filterRows[$0] { return true } else { return false } }
    }

    /// Selects the filter row at `index`, or the nearest filter row in `direction`.
    private func selectFilter(near index: Int, direction: Int) {
        let indices = filterIndices
        guard let first = indices.first, let last = indices.last else { selectedFilterIndex = nil; return }
        if index <= first { selectedFilterIndex = first; return }
        if index >= last { selectedFilterIndex = last; return }
        if direction >= 0 {
            selectedFilterIndex = indices.first { $0 >= index }
        } else {
            selectedFilterIndex = indices.last { $0 <= index }
        }
    }

    private func moveFilterSelection(by delta: Int) {
        let indices = filterIndices
        guard !indices.isEmpty else { return }
        let position = selectedFilterIndex.flatMap { indices.firstIndex(of: $0) } ?? 0
        selectedFilterIndex = indices[min(max(0, position + delta), indices.count - 1)]
        scrollToSelection()
    }

    // MARK: keys

    func handle(_ key: PickerKey) -> PickerAction {
        switch step {
        case .clips: return handleClipKey(key)
        case .filters(let clipID): return handleFilterKey(key, clipID: clipID)
        }
    }

    private func handleClipKey(_ key: PickerKey) -> PickerAction {
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
            return selectedClip.map { .recall($0.id, defaultFormat) } ?? .none
        case .enterAlternate:
            return selectedClip.map { .recall($0.id, alternateFormat) } ?? .none
        case .enterFilter:
            guard let clip = selectedClip else { return .none }
            openFilters(for: clip.id)
        case .recallNumber(let number):
            let index = firstRow + number - 1
            guard number >= 1, number <= 9, index < rows.count, index < firstRow + visibleRowCount else { return .none }
            return .recall(rows[index].id, defaultFormat)
        case .deleteBackward, .deleteWordBackward, .clearQuery, .text:
            if let edited = Self.edit(query, with: key), edited != query {
                query = edited
                reload()
            }
        }
        return .none
    }

    private func handleFilterKey(_ key: PickerKey, clipID: Int64) -> PickerAction {
        switch key {
        case .up: moveFilterSelection(by: -1)
        case .down: moveFilterSelection(by: 1)
        case .pageUp: moveFilterSelection(by: -visibleRowCount)
        case .pageDown: moveFilterSelection(by: visibleRowCount)
        case .home: moveFilterSelection(by: -filterRows.count)
        case .end: moveFilterSelection(by: filterRows.count)
        case .escape: closeFilters()
        case .tab, .recallNumber, .enterFilter: break
        case .enter, .enterAlternate:
            return selectedFilter.map { .recall(clipID, .filter($0.id)) } ?? .none
        case .deleteBackward, .deleteWordBackward, .clearQuery, .text:
            if let edited = Self.edit(filterQuery, with: key), edited != filterQuery {
                filterQuery = edited
                reloadFilters()
            }
        }
        return .none
    }

    private func openFilters(for clipID: Int64) {
        savedClipState = (query, selectedIndex, firstRow)
        step = .filters(clipID: clipID)
        previewOpen = false
        filterQuery = ""
        reloadFilters()
    }

    private func closeFilters() {
        step = .clips
        if let saved = savedClipState {
            selectedIndex = saved.selected
            firstRow = saved.first
        }
        savedClipState = nil
    }

    private func reloadFilters() {
        let matching = TextFilter.matching(filterQuery)
        filterRows = TextFilter.Group.allCases.flatMap { group -> [FilterRow] in
            let filters = matching.filter { $0.group == group }
            return filters.isEmpty ? [] : [.heading(group)] + filters.map { .filter($0) }
        }
        firstFilterRow = 0
        selectedFilterIndex = filterIndices.first
    }

    /// The query after an editing key, or nil for keys that do not edit.
    static func edit(_ text: String, with key: PickerKey) -> String? {
        switch key {
        case .deleteBackward:
            return String(text.dropLast())
        case .deleteWordBackward:
            var edited = Substring(text)
            while edited.last?.isWhitespace == true { edited = edited.dropLast() }
            while let last = edited.last, !last.isWhitespace { edited = edited.dropLast() }
            return String(edited)
        case .clearQuery:
            return ""
        case .text(let characters):
            let printable = characters.filter {
                !$0.isNewline && !($0.unicodeScalars.first.map { CharacterSet.controlCharacters.contains($0) } ?? false)
            }
            return text + printable
        default:
            return nil
        }
    }
}
