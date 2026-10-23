import SwiftUI

/// View-local mutable state. The macOS 27 SDK implements `@State` as a macro whose plugin ships
/// only with Xcode, so this package (buildable with the Command Line Tools alone) keeps view-local
/// values in a `@StateObject` box instead.
final class ViewState<Value>: ObservableObject {
    @Published var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
