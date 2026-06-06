import SwiftUI
import StatsUsageDomain

/// Sidebar + detail settings layout. Uses a plain HSplitView-equivalent so
/// macOS never injects a sidebar-toggle toolbar button.
struct SettingsRootView: View {
    @Bindable var viewModel: AppViewModel
    @State private var selection: SettingsTab = .general

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case menuBar = "Menu Bar"
        case notch = "Notch"
        case providers = "Providers"
        case history = "History"
        case about = "About"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .general:   return "gearshape"
            case .menuBar:   return "menubar.rectangle"
            case .notch:     return "rectangle.topthird.inset.filled"
            case .providers: return "square.stack.3d.up"
            case .history:   return "chart.xyaxis.line"
            case .about:     return "info.circle"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert(item: $viewModel.userFacingError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK")) { viewModel.dismissUserFacingError() }
            )
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(SettingsTab.allCases, selection: $selection) { tab in
            Label(tab.rawValue, systemImage: tab.systemImage)
                .tag(tab)
        }
        .listStyle(.sidebar)
        .frame(width: 180)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general:   GeneralSettingsView(viewModel: viewModel)
        case .menuBar:   MenuBarSettingsView(viewModel: viewModel)
        case .notch:     NotchSettingsView(viewModel: viewModel)
        case .providers: ProvidersSettingsView(viewModel: viewModel)
        case .history:   HistorySettingsView(viewModel: viewModel)
        case .about:     AboutSettingsView(viewModel: viewModel)
        }
    }
}
