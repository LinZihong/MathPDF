import SwiftUI

struct ReaderCommandContext {
    let togglePreambleInspector: () -> Void
    let focusSearch: () -> Void
}

struct ReaderCommandContextKey: FocusedValueKey {
    typealias Value = ReaderCommandContext
}

extension FocusedValues {
    var readerCommandContext: ReaderCommandContext? {
        get { self[ReaderCommandContextKey.self] }
        set { self[ReaderCommandContextKey.self] = newValue }
    }
}
