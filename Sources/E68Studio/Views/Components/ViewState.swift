import SwiftUI

/// The macOS 27 SDK turns `@State` into a compiler macro whose plugin ships only with
/// full Xcode. Spelling the property wrapper through this alias keeps the project
/// buildable with just the Command Line Tools, and behaves identically.
typealias ViewState<Value> = SwiftUI.State<Value>
