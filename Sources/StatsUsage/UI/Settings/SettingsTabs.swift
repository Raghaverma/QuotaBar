import SwiftUI
import StatsUsageDomain

/// General preferences: language, launch at login, resource mode.
struct GeneralSettingsView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        Form {
            Section {
                Picker(selection: languageBinding) {
                    Text("English").tag(AppLanguage.en)
                    Text("简体中文").tag(AppLanguage.zhHans)
                } label: {
                    SettingRowLabel(icon: "globe", color: .blue,
                                    title: "Language",
                                    subtitle: "Interface display language")
                }
            } header: {
                Text("Appearance")
            }

            Section {
                Toggle(isOn: launchAtLoginBinding) {
                    SettingRowLabel(icon: "power", color: .green,
                                    title: "Launch at login",
                                    subtitle: "Start StatsUsage automatically when you sign in")
                }
            } header: {
                Text("Startup")
            }

            Section {
                Toggle(isOn: autoUpdateBinding) {
                    SettingRowLabel(icon: "arrow.triangle.2.circlepath", color: .purple,
                                    title: "Automatically check for updates",
                                    subtitle: "Keep StatsUsage fresh with the latest features")
                }
            } header: {
                Text("Updates")
            }

            Section {
                Picker(selection: resourceModeBinding) {
                    Text("Responsive — 3 min").tag(ResourceMode.responsive)
                    Text("Balanced — 5 min").tag(ResourceMode.balanced)
                    Text("Relaxed — 10 min").tag(ResourceMode.relaxed)
                    Text("Low power — 15 min").tag(ResourceMode.lowPower)
                } label: {
                    SettingRowLabel(icon: "bolt.fill", color: .orange,
                                    title: "Resource mode",
                                    subtitle: "How often providers are refreshed")
                }
            } header: {
                Text("Performance")
            } footer: {
                Text("Longer intervals reduce battery, CPU, and network usage.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(get: { viewModel.config.language },
                set: { newValue in viewModel.updateConfig { $0.language = newValue } })
    }
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(get: { viewModel.config.launchAtLoginEnabled },
                set: { newValue in viewModel.updateConfig { $0.launchAtLoginEnabled = newValue } })
    }
    private var autoUpdateBinding: Binding<Bool> {
        Binding(get: { viewModel.config.autoUpdateEnabled },
                set: { newValue in viewModel.updateConfig { $0.autoUpdateEnabled = newValue } })
    }
    private var resourceModeBinding: Binding<ResourceMode> {
        Binding(get: { viewModel.config.resourceMode },
                set: { newValue in viewModel.updateConfig { $0.resourceMode = newValue } })
    }
}

/// Menu-bar preferences: which provider drives the text, display style, appearance.
struct MenuBarSettingsView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        Form {
            Section {
                Picker(selection: statusProviderBinding) {
                    Text("Auto").tag(String?.none)
                    ForEach(viewModel.config.providers) { provider in
                        Text(provider.name).tag(String?.some(provider.id))
                    }
                } label: {
                    SettingRowLabel(icon: "chart.bar.fill", color: .indigo,
                                    title: "Status-bar provider",
                                    subtitle: "Which provider drives the menu-bar readout")
                }
            } header: {
                Text("Content")
            }

            Section {
                Picker(selection: widgetStyleBinding) {
                    ForEach(MenuBarWidgetStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                } label: {
                    SettingRowLabel(icon: "textformat", color: .teal,
                                    title: "Widget style",
                                    subtitle: "How the value is rendered in the menu bar")
                }
                Picker(selection: appearanceBinding) {
                    Text("Follow wallpaper").tag(StatusBarAppearanceMode.followWallpaper)
                    Text("Dark").tag(StatusBarAppearanceMode.dark)
                    Text("Light").tag(StatusBarAppearanceMode.light)
                } label: {
                    SettingRowLabel(icon: "circle.lefthalf.filled", color: .gray,
                                    title: "Appearance",
                                    subtitle: "Tint of the menu-bar widget")
                }
            } header: {
                Text("Appearance")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Menu Bar")
    }

    private var statusProviderBinding: Binding<String?> {
        Binding(get: { viewModel.config.statusBarProviderID },
                set: { newValue in viewModel.updateConfig { $0.statusBarProviderID = newValue } })
    }
    private var widgetStyleBinding: Binding<MenuBarWidgetStyle> {
        Binding(get: { viewModel.config.menuBarWidgetStyle },
                set: { newValue in viewModel.updateConfig { $0.menuBarWidgetStyle = newValue } })
    }
    private var appearanceBinding: Binding<StatusBarAppearanceMode> {
        Binding(get: { viewModel.config.statusBarAppearanceMode },
                set: { newValue in viewModel.updateConfig { $0.statusBarAppearanceMode = newValue } })
    }
}

/// Notch hub preferences: enable, which provider drives the collapsed readout,
/// and whether it expands on hover.
struct NotchSettingsView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: enabledBinding) {
                    SettingRowLabel(icon: "rectangle.topthird.inset.filled", color: .pink,
                                    title: "Show notch hub",
                                    subtitle: "A live usage island that hugs the notch")
                }
            } footer: {
                Text("The hub sits at the top-center of the screen, hugging the notch on Macs that have one. Hover to expand into a live usage panel; click to open Settings.")
            }

            Section {
                Picker(selection: providerBinding) {
                    Text("First available").tag(String?.none)
                    ForEach(viewModel.config.providers) { provider in
                        Text(provider.name).tag(String?.some(provider.id))
                    }
                } label: {
                    SettingRowLabel(icon: "star.fill", color: .yellow,
                                    title: "Collapsed provider",
                                    subtitle: "Shown on the notch when not expanded")
                }
                .disabled(!viewModel.config.notchEnabled)

                Toggle(isOn: expandBinding) {
                    SettingRowLabel(icon: "arrow.down.left.and.arrow.up.right", color: .purple,
                                    title: "Expand on hover",
                                    subtitle: "Reveal the full panel when you hover")
                }
                .disabled(!viewModel.config.notchEnabled)
            } header: {
                Text("Behavior")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Notch")
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { viewModel.config.notchEnabled },
                set: { newValue in viewModel.updateConfig { $0.notchEnabled = newValue } })
    }
    private var providerBinding: Binding<String?> {
        Binding(get: { viewModel.config.notchProviderID },
                set: { newValue in viewModel.updateConfig { $0.notchProviderID = newValue } })
    }
    private var expandBinding: Binding<Bool> {
        Binding(get: { viewModel.config.notchExpandOnHover },
                set: { newValue in viewModel.updateConfig { $0.notchExpandOnHover = newValue } })
    }
}

/// Providers list: enable/disable and poll interval per provider.
struct ProvidersSettingsView: View {
    @Bindable var viewModel: AppViewModel
    @State private var configuringProviderID: String?

    var body: some View {
        Form {
            Section {
                ForEach(viewModel.config.providers) { provider in
                    HStack(spacing: 11) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(
                                (provider.enabled ? Color.accentColor : Color.gray).gradient,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )

                        VStack(alignment: .leading, spacing: 1) {
                            Text(provider.name)
                            Text(provider.type.rawValue.capitalized + " · every \(provider.pollIntervalSec / 60) min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            configuringProviderID = provider.id
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .buttonStyle(.borderless)
                        .help("Configure settings and credentials")

                        Toggle("", isOn: enabledBinding(provider.id))
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Providers")
            } footer: {
                Text("Toggle a provider on or off, or open its configuration to set credentials, poll interval, and alert thresholds.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Providers")
        .sheet(item: Binding(
            get: { configuringProviderID.map { IdentifiableString(id: $0) } },
            set: { configuringProviderID = $0?.id }
        )) { configItem in
            ConfigureProviderSheet(providerID: configItem.id, viewModel: viewModel)
        }
    }

    private func enabledBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.config.providers.first(where: { $0.id == id })?.enabled ?? false },
            set: { newValue in
                viewModel.updateConfig { config in
                    if let idx = config.providers.firstIndex(where: { $0.id == id }) {
                        config.providers[idx].enabled = newValue
                    }
                }
            }
        )
    }
}

struct IdentifiableString: Identifiable {
    let id: String
}

struct ConfigureProviderSheet: View {
    let providerID: String
    var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var pollIntervalMinutes: Int = 5
    @State private var apiKey: String = ""
    @State private var baseURL: String = ""
    @State private var userID: String = ""
    @State private var groupID: String = ""

    // Alert thresholds (mirror of the provider's AlertRule).
    @State private var lowRemaining: Double = 10
    @State private var maxConsecutiveFailures: Int = 3
    @State private var notifyOnAuthError: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    TextField("Display Name", text: $name)
                    Picker("Poll Interval", selection: $pollIntervalMinutes) {
                        Text("1 min").tag(1)
                        Text("3 min").tag(3)
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                    }
                }
                
                Section("Security / Credentials") {
                    SecureField("API Key / Token", text: $apiKey)
                }

                Section("Alerts") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Low-remaining alert")
                            Spacer()
                            Text("\(Int(lowRemaining))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $lowRemaining, in: 0...100, step: 1)
                        Text("Notify when remaining quota falls to or below this level.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Stepper(value: $maxConsecutiveFailures, in: 0...20) {
                        HStack {
                            Text("Failure alert")
                            Spacer()
                            Text(maxConsecutiveFailures == 0
                                 ? "Off"
                                 : "After \(maxConsecutiveFailures) failures")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle("Notify on auth / sign-in errors", isOn: $notifyOnAuthError)
                }

                if isRelay {
                    Section("Relay Settings") {
                        TextField("Base URL", text: $baseURL)
                        TextField("User ID (Optional)", text: $userID)
                        TextField("Group ID (Optional)", text: $groupID)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Configure \(name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                load()
            }
        }
        .frame(width: 400, height: isRelay ? 640 : 500)
    }

    private var isRelay: Bool {
        viewModel.config.providers.first(where: { $0.id == providerID })?.isRelay ?? false
    }

    private func load() {
        guard let provider = viewModel.config.providers.first(where: { $0.id == providerID }) else { return }
        name = provider.name
        pollIntervalMinutes = provider.pollIntervalSec / 60
        apiKey = viewModel.getSecret(for: providerID) ?? ""
        lowRemaining = provider.threshold.lowRemaining
        maxConsecutiveFailures = provider.threshold.maxConsecutiveFailures
        notifyOnAuthError = provider.threshold.notifyOnAuthError
        if let relay = provider.relayConfig {
            baseURL = relay.baseURL
            userID = relay.userID ?? ""
            groupID = relay.groupID ?? ""
        }
    }

    private func save() {
        // Save keychain secret
        if !apiKey.isEmpty {
            viewModel.setSecret(apiKey, for: providerID)
        }
        
        // Save config
        viewModel.updateConfig { config in
            if let idx = config.providers.firstIndex(where: { $0.id == providerID }) {
                config.providers[idx].name = name
                config.providers[idx].pollIntervalSec = pollIntervalMinutes * 60
                config.providers[idx].threshold = AlertRule(
                    lowRemaining: lowRemaining,
                    maxConsecutiveFailures: maxConsecutiveFailures,
                    notifyOnAuthError: notifyOnAuthError
                )
                if isRelay {
                    config.providers[idx].relayConfig?.baseURL = baseURL
                    config.providers[idx].relayConfig?.userID = userID.isEmpty ? nil : userID
                    config.providers[idx].relayConfig?.groupID = groupID.isEmpty ? nil : groupID
                }
            }
        }
    }
}

/// About tab: app identity, version, and links.
struct AboutSettingsView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .padding(20)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(spacing: 4) {
                Text("StatsUsage").font(.title.bold())
                Text("Version \(AppVersion.current)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("A menu-bar console for AI subscription usage.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)

            Divider()
                .frame(maxWidth: 280)
                .padding(.vertical, 8)

            // Update Section
            VStack(spacing: 12) {
                switch viewModel.updateState {
                case .idle:
                    Button(action: {
                        Task {
                            await viewModel.checkForUpdates()
                        }
                    }) {
                        Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                            .frame(minWidth: 150)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                case .checking:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking for updates...")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    
                case .upToDate:
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("StatsUsage is up to date")
                                .bold()
                        }
                        Button("Check Again") {
                            Task {
                                await viewModel.checkForUpdates()
                            }
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                    .font(.callout)
                    
                case .available(let manifest):
                    VStack(spacing: 10) {
                        Text("New Version Available: \(manifest.version)")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        Button(action: {
                            Task {
                                await viewModel.installAvailableUpdate()
                            }
                        }) {
                            Text("Download and Install Update")
                                .frame(minWidth: 180)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.large)
                        
                        if let url = URL(string: manifest.release_url) {
                            Link("View Release Notes", destination: url)
                                .font(.caption)
                        }
                    }
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: 320)
                    
                case .downloading:
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Downloading update...")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    
                case .installing:
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Installing and relaunching...")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    
                case .error(let error):
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text("Update failed")
                                .bold()
                        }
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 280)
                        
                        Button("Try Again") {
                            Task {
                                await viewModel.checkForUpdates()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .font(.callout)
                }
            }
            .frame(height: 100)

            Divider()
                .frame(maxWidth: 280)
                .padding(.vertical, 8)

            HStack(spacing: 10) {
                Link(destination: URL(string: "https://github.com/Raghaverma/UsageStats")!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://github.com/Raghaverma/UsageStats/issues")!) {
                    Label("Report an issue", systemImage: "exclamationmark.bubble")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()

            Text("© 2026 StatsUsage · MIT License")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("About")
    }
}
