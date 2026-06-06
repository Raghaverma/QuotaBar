import SwiftUI
import StatsUsageDomain

/// General preferences: language, launch at login, resource mode.
struct GeneralSettingsView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        Form {
            Picker("Language", selection: languageBinding) {
                Text("English").tag(AppLanguage.en)
                Text("简体中文").tag(AppLanguage.zhHans)
            }
            Toggle("Launch at login", isOn: launchAtLoginBinding)
            Picker("Resource mode", selection: resourceModeBinding) {
                Text("Responsive (3 min)").tag(ResourceMode.responsive)
                Text("Balanced (5 min)").tag(ResourceMode.balanced)
                Text("Relaxed (10 min)").tag(ResourceMode.relaxed)
                Text("Low power (15 min)").tag(ResourceMode.lowPower)
            }
        }
        .formStyle(.grouped)
        .padding()
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
            Picker("Status-bar provider", selection: statusProviderBinding) {
                Text("Auto").tag(String?.none)
                ForEach(viewModel.config.providers) { provider in
                    Text(provider.name).tag(String?.some(provider.id))
                }
            }
            Picker("Widget style", selection: widgetStyleBinding) {
                ForEach(MenuBarWidgetStyle.allCases, id: \.self) { style in
                    Text(style.title).tag(style)
                }
            }
            Picker("Appearance", selection: appearanceBinding) {
                Text("Follow wallpaper").tag(StatusBarAppearanceMode.followWallpaper)
                Text("Dark").tag(StatusBarAppearanceMode.dark)
                Text("Light").tag(StatusBarAppearanceMode.light)
            }
        }
        .formStyle(.grouped)
        .padding()
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
            Toggle("Show notch hub", isOn: enabledBinding)
            Picker("Collapsed provider", selection: providerBinding) {
                Text("First available").tag(String?.none)
                ForEach(viewModel.config.providers) { provider in
                    Text(provider.name).tag(String?.some(provider.id))
                }
            }
            .disabled(!viewModel.config.notchEnabled)
            Toggle("Expand on hover", isOn: expandBinding)
                .disabled(!viewModel.config.notchEnabled)
            Text("The hub floats at the top-center of the screen, hugging the notch on Macs that have one. Hover to expand into a live usage panel; click to open Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
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
        List {
            ForEach(viewModel.config.providers) { provider in
                HStack {
                    Toggle(isOn: enabledBinding(provider.id)) {
                        VStack(alignment: .leading) {
                            Text(provider.name)
                            Text(provider.type.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(provider.pollIntervalSec / 60) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        configuringProviderID = provider.id
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.borderless)
                    .help("Configure settings and credentials")
                }
            }
        }
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

/// About tab: version + update check.
struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("StatsUsage").font(.title2.bold())
            Text("Version \(AppVersion.current)").foregroundStyle(.secondary)
            Text("A menu-bar console for AI subscription usage.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("About")
    }
}
