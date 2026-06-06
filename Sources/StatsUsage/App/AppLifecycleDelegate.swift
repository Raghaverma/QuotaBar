import AppKit

/// The real entry-point work: make the app an accessory (no Dock icon), enforce a
/// single instance, and construct the view model + status bar controller.
@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    private var viewModel: AppViewModel?
    private var statusBarController: StatusBarController?
    private var notchHubController: NotchHubController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menu bar only

        guard SingleInstanceLock.shared.acquire() else {
            // Another StatsUsage is already running. Make the early exit obvious in
            // the console instead of a mysterious "exit code 0".
            NSLog("[StatsUsage] Another instance is already running — quitting this one. " +
                  "Run `pkill StatsUsage` to stop it, then relaunch.")
            NSApp.terminate(nil)
            return
        }

        let vm = AppViewModel()
        viewModel = vm
        let statusBar = StatusBarController(viewModel: vm)
        statusBarController = statusBar
        notchHubController = NotchHubController(
            viewModel: vm,
            onOpenSettings: { [weak statusBar] in statusBar?.openSettings() }
        )

        Task {
            try? await Task.sleep(for: .seconds(3))
            await vm.checkForUpdates(quietly: true)
            // Re-check every 24 hours for the lifetime of the process.
            let day: UInt64 = 24 * 60 * 60 * 1_000_000_000
            while true {
                try? await Task.sleep(nanoseconds: day)
                await vm.checkForUpdates(quietly: true)
            }
        }
    }
}
