import AppKit
import SwiftUI
import Observation
import QuotaBarDomain
import QuotaBarPresentation

/// Orchestrates the menu-bar presence: owns the status item, a popover hosting the
/// SwiftUI menu, and observes the view model to re-render the status item on change.
@MainActor
final class StatusBarController {
    private let viewModel: AppViewModel
    private let statusItem = StatusItemController()
    private let popover = NSPopover()
    private var settingsWindowController: SettingsWindowController?

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 360)
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView(
                viewModel: viewModel,
                onQuit: { NSApp.terminate(nil) },
                onOpenSettings: { [weak self] in self?.openSettings() }
            )
        )

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        viewModel.start()
        observeAndRender()
    }

    /// Re-establish observation each render so changes to snapshots/config retrigger.
    private func observeAndRender() {
        withObservationTracking {
            renderStatusItem()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeAndRender() }
        }
    }

    private func renderStatusItem() {
        let entries = menuBarEntries()
        let dark = isMenuBarDark()
        statusItem.render(
            entries: entries,
            style: viewModel.config.menuBarWidgetStyle,
            history: viewModel.usageHistory,
            appearanceDark: dark
        )
    }

    /// Build the menu-bar entries from config + snapshots.
    private func menuBarEntries() -> [StatusBarDisplayEntry] {
        let config = viewModel.config
        let ids: [String]
        if config.statusBarMultiUsageEnabled, !config.statusBarMultiProviderIDs.isEmpty {
            ids = config.statusBarMultiProviderIDs
        } else if let single = config.statusBarProviderID {
            ids = [single]
        } else {
            // Default: the first enabled, menu-bar-visible provider with a snapshot.
            ids = config.providers
                .filter { $0.enabled && $0.showsInMenuBar }
                .map(\.id)
        }
        return ids.compactMap { id in
            guard let snapshot = viewModel.snapshots[id] else { return nil }
            let name = config.providers.first(where: { $0.id == id })?.name ?? id
            return StatusBarDisplayPresenter.makeEntry(name: name, snapshot: snapshot, maskValues: config.hideUsageValuesEnabled)
        }
    }

    private func isMenuBarDark() -> Bool {
        switch viewModel.config.statusBarAppearanceMode {
        case .dark: return true
        case .light: return false
        case .followWallpaper:
            let appearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
            return appearance == .darkAqua
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(viewModel: viewModel)
        }
        popover.performClose(nil)
        settingsWindowController?.show()
    }
}
