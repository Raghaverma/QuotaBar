import SwiftUI
import StatsUsageDomain
import StatsUsagePresentation

/// The popover body: a card per provider plus a footer with refresh / quit.
struct MenuContentView: View {
    @Bindable var viewModel: AppViewModel
    var onQuit: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("StatsUsage").font(.headline)
                Spacer()
                Button {
                    viewModel.refreshNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh now")
            }

            if viewModel.lastLoadWasLossy {
                Label("Some saved providers couldn't be read and were skipped.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Divider()

            if enabledProviders.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Welcome to StatsUsage").font(.subheadline.bold())
                    Text("Enable a provider in Settings to begin monitoring your AI quotas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Provider Setup", action: onOpenSettings)
                        .buttonStyle(.link)
                }
                .padding(.vertical, 8)
            } else {
                ForEach(enabledProviders) { provider in
                    ProviderCardView(
                        snapshot: viewModel.snapshots[provider.id],
                        name: provider.name,
                        error: viewModel.errors[provider.id],
                        isRefreshing: viewModel.refreshingProviderIDs.contains(provider.id),
                        trend: viewModel.trendDescription(for: provider.id),
                        showAccount: viewModel.config.showOfficialAccountEmailInMenuBar,
                        onRetry: { viewModel.testConnection(providerID: provider.id) }
                    )
                }
            }

            Divider()

            HStack {
                Button("Settings…", action: onOpenSettings)
                Spacer()
                Button("Quit", action: onQuit)
            }
            .font(.caption)
        }
        .padding(12)
        .frame(width: 320)
    }

    private var enabledProviders: [ProviderDescriptor] {
        viewModel.config.providers.filter(\.enabled)
    }
}

/// One provider card: name, value, freshness, and any quota windows with countdowns.
struct ProviderCardView: View {
    let snapshot: UsageSnapshot?
    let name: String
    let error: String?
    let isRefreshing: Bool
    let trend: String?
    let showAccount: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(name).font(.subheadline.bold())
                Spacer()
                if isRefreshing {
                    ProgressView().controlSize(.mini)
                }
                Text(primaryValue).font(.subheadline.monospacedDigit())
            }
            if showAccount, let account = snapshot?.accountLabel {
                Text(account).font(.caption2).foregroundStyle(.secondary)
            }
            if let error {
                Text(error).font(.caption2).foregroundStyle(.red)
                Button("Retry", action: onRetry).buttonStyle(.link).font(.caption2)
            } else if let snapshot, !snapshot.note.isEmpty {
                Text(snapshot.note).font(.caption2).foregroundStyle(.secondary)
            }
            if let trend {
                Text(trend).font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(snapshot?.quotaWindows ?? []) { window in
                HStack {
                    Text(window.title).font(.caption2)
                    Spacer()
                    Text(MenuQuotaPresenter.remainingText(window)).font(.caption2)
                    if let countdown = MenuQuotaPresenter.resetCountdown(window) {
                        Text("· \(countdown)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var primaryValue: String {
        if let pct = snapshot?.remainingPercent { return "\(Int(pct.rounded()))%" }
        if let remaining = snapshot?.remaining { return "\(Int(remaining)) \(snapshot?.unit ?? "")" }
        return "—"
    }

    private var statusColor: Color {
        guard let snapshot else { return isRefreshing ? .blue : .gray }
        switch snapshot.status {
        case .ok: return snapshot.valueFreshness == .cachedFallback ? .yellow : .green
        case .warning: return .yellow
        case .error: return .red
        case .disabled: return .gray
        }
    }
}
