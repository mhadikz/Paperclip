import SwiftUI

/// Local view state.
///
/// Use `@ViewState` everywhere this project would normally write `@State`.
///
/// Starting with the macOS 26/27 SDKs, the `@State` attribute resolves to a
/// Swift macro (`SwiftUIMacros.StateMacro`) whose plugin only ships inside
/// Xcode. Builds driven by the Command Line Tools (`scripts/build.sh`) cannot
/// expand it and fail with "plugin for module 'SwiftUIMacros' not found".
///
/// The underlying `SwiftUI.State<Value>` property wrapper still exists, and a
/// typealias resolves to that struct instead of the macro, so `@ViewState`
/// keeps the exact runtime semantics of `@State` while compiling with both
/// Xcode and the Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>
