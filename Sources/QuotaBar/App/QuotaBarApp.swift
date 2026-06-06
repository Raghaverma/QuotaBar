import AppKit
import SwiftUI

/// Menu-bar-only SwiftUI app. The empty `Settings` scene keeps SwiftUI happy while
/// the `NSApplicationDelegate` does the real work.
@main
struct StatsUsageApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
