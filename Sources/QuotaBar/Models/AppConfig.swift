import Foundation
import QuotaBarDomain

enum AppLanguage: String, Codable, Sendable { case zhHans, en }

/// Maps a friendly resource mode to a background poll cadence, decoding legacy aliases.
enum ResourceMode: String, Codable, Sendable {
    case responsive, balanced, relaxed, lowPower

    var backgroundPollIntervalSeconds: Int {
        switch self {
        case .responsive: return 180   // 3 min
        case .balanced:   return 300   // 5 min
        case .relaxed:    return 600   // 10 min
        case .lowPower:   return 900   // 15 min
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "responsive": self = .responsive
        case "balanced":   self = .balanced
        case "relaxed":    self = .relaxed
        case "lowPower":   self = .lowPower
        default:           self = .balanced   // legacy/unknown → safe default
        }
    }
}

enum StatusBarAppearanceMode: String, Codable, Sendable {
    case followWallpaper, dark, light
}

enum StatusBarDisplayStyle: String, Codable, Sendable {
    case iconPercent, barNamePercent
}

/// The Stats-style rendering for the menu-bar widget.
enum MenuBarWidgetStyle: String, Codable, CaseIterable, Sendable {
    case percent     // compact "Name 42%" text
    case bar         // vertical-bar gauge of remaining quota
    case sparkline   // tiny line chart of recent usage
    case ring        // circular ring filled to remaining-percent

    var title: String {
        switch self {
        case .percent: return "Percentage / text"
        case .bar: return "Bar chart"
        case .sparkline: return "Mini graph"
        case .ring: return "Ring gauge"
        }
    }
}

/// Top-level persisted config. Decodes additively so old files keep loading.
struct AppConfig: Codable, Equatable, Sendable {
    var language: AppLanguage
    var resourceMode: ResourceMode
    var launchAtLoginEnabled: Bool
    var showOfficialAccountEmailInMenuBar: Bool
    var hideUsageValuesEnabled: Bool
    var statusBarProviderID: String?
    var statusBarMultiUsageEnabled: Bool
    var statusBarMultiProviderIDs: [String]
    var statusBarAppearanceMode: StatusBarAppearanceMode
    var statusBarDisplayStyle: StatusBarDisplayStyle
    var menuBarWidgetStyle: MenuBarWidgetStyle
    var notchEnabled: Bool
    var notchProviderID: String?
    var notchExpandOnHover: Bool
    var autoUpdateEnabled: Bool
    var providers: [ProviderDescriptor]

    init(
        language: AppLanguage = .en,
        resourceMode: ResourceMode = .balanced,
        launchAtLoginEnabled: Bool = false,
        showOfficialAccountEmailInMenuBar: Bool = false,
        hideUsageValuesEnabled: Bool = false,
        statusBarProviderID: String? = nil,
        statusBarMultiUsageEnabled: Bool = false,
        statusBarMultiProviderIDs: [String] = [],
        statusBarAppearanceMode: StatusBarAppearanceMode = .followWallpaper,
        statusBarDisplayStyle: StatusBarDisplayStyle = .iconPercent,
        menuBarWidgetStyle: MenuBarWidgetStyle = .percent,
        notchEnabled: Bool = true,
        notchProviderID: String? = nil,
        notchExpandOnHover: Bool = true,
        autoUpdateEnabled: Bool = true,
        providers: [ProviderDescriptor] = ProviderDefaultCatalog.seedProviders()
    ) {
        self.language = language
        self.resourceMode = resourceMode
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.showOfficialAccountEmailInMenuBar = showOfficialAccountEmailInMenuBar
        self.hideUsageValuesEnabled = hideUsageValuesEnabled
        self.statusBarProviderID = statusBarProviderID
        self.statusBarMultiUsageEnabled = statusBarMultiUsageEnabled
        self.statusBarMultiProviderIDs = statusBarMultiProviderIDs
        self.statusBarAppearanceMode = statusBarAppearanceMode
        self.statusBarDisplayStyle = statusBarDisplayStyle
        self.menuBarWidgetStyle = menuBarWidgetStyle
        self.notchEnabled = notchEnabled
        self.notchProviderID = notchProviderID
        self.notchExpandOnHover = notchExpandOnHover
        self.autoUpdateEnabled = autoUpdateEnabled
        self.providers = providers
    }

    static let `default` = AppConfig()

    private enum CodingKeys: String, CodingKey {
        case language, resourceMode, launchAtLoginEnabled, showOfficialAccountEmailInMenuBar
        case hideUsageValuesEnabled
        case statusBarProviderID, statusBarMultiUsageEnabled, statusBarMultiProviderIDs
        case statusBarAppearanceMode, statusBarDisplayStyle, menuBarWidgetStyle
        case notchEnabled, notchProviderID, notchExpandOnHover, autoUpdateEnabled, providers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .en
        resourceMode = try c.decodeIfPresent(ResourceMode.self, forKey: .resourceMode) ?? .balanced
        launchAtLoginEnabled = try c.decodeIfPresent(Bool.self, forKey: .launchAtLoginEnabled) ?? false
        showOfficialAccountEmailInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showOfficialAccountEmailInMenuBar) ?? false
        hideUsageValuesEnabled = try c.decodeIfPresent(Bool.self, forKey: .hideUsageValuesEnabled) ?? false
        statusBarProviderID = try c.decodeIfPresent(String.self, forKey: .statusBarProviderID)
        statusBarMultiUsageEnabled = try c.decodeIfPresent(Bool.self, forKey: .statusBarMultiUsageEnabled) ?? false
        statusBarMultiProviderIDs = try c.decodeIfPresent([String].self, forKey: .statusBarMultiProviderIDs) ?? []
        statusBarAppearanceMode = try c.decodeIfPresent(StatusBarAppearanceMode.self, forKey: .statusBarAppearanceMode) ?? .followWallpaper
        statusBarDisplayStyle = try c.decodeIfPresent(StatusBarDisplayStyle.self, forKey: .statusBarDisplayStyle) ?? .iconPercent
        menuBarWidgetStyle = try c.decodeIfPresent(MenuBarWidgetStyle.self, forKey: .menuBarWidgetStyle) ?? .percent
        notchEnabled = try c.decodeIfPresent(Bool.self, forKey: .notchEnabled) ?? true
        notchProviderID = try c.decodeIfPresent(String.self, forKey: .notchProviderID)
        notchExpandOnHover = try c.decodeIfPresent(Bool.self, forKey: .notchExpandOnHover) ?? true
        autoUpdateEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoUpdateEnabled) ?? true
        providers = try Self.decodeProvidersLossily(from: c)
    }

    /// Lossy-tolerant provider decoding: skip entries we can't decode (counting them)
    /// rather than failing the whole file.
    private static func decodeProvidersLossily(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [ProviderDescriptor] {
        guard container.contains(.providers) else { return AppConfig.default.providers }
        var unkeyed = try container.nestedUnkeyedContainer(forKey: .providers)
        var result: [ProviderDescriptor] = []
        var dropped = 0
        while !unkeyed.isAtEnd {
            // FailableDecodable always succeeds (advancing the index), so a single
            // malformed entry can never abort the whole array.
            let wrapper = try unkeyed.decode(FailableDecodable<ProviderDescriptor>.self)
            if let provider = wrapper.value {
                result.append(provider)
            } else {
                dropped += 1
            }
        }
        AppConfig.lastDecodeDroppedCount = dropped
        return result
    }

    /// Records how many provider entries were skipped by the most recent decode.
    nonisolated(unsafe) static var lastDecodeDroppedCount = 0
}

/// Wraps a decode so failure yields `nil` while still consuming the element.
private struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
