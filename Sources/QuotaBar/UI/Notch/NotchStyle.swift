import SwiftUI
import QuotaBarDomain

/// The three-tier health colour used everywhere in the hub. These are the *same* RGB
/// values the menu-bar widget uses (`MenuBarWidgetRenderer.color`), so a provider that
/// looks amber in the menu bar looks amber in the notch — one visual language.
enum NotchStatus: Equatable {
    case healthy    // plenty of quota left
    case warning    // getting low
    case critical   // nearly out
    case unknown    // no data / unhealthy fetch

    /// Derive a status from a remaining-percent value and whether the fetch was healthy.
    static func from(remainingPercent pct: Double?, isHealthy: Bool) -> NotchStatus {
        guard isHealthy, let pct else { return .unknown }
        switch pct {
        case ..<20: return .critical
        case ..<50: return .warning
        default:    return .healthy
        }
    }

    var color: Color {
        switch self {
        case .healthy:  return Color(red: 0.0, green: 0.90, blue: 0.46)
        case .warning:  return Color(red: 1.0, green: 0.63, blue: 0.0)
        case .critical: return Color(red: 1.0, green: 0.18, blue: 0.33)
        case .unknown:  return Color(red: 0.55, green: 0.55, blue: 0.57)
        }
    }

    /// Ordering for "worst of" reductions across providers (critical is worst).
    private var severity: Int {
        switch self {
        case .critical: return 3
        case .warning:  return 2
        case .healthy:  return 1
        case .unknown:  return 0
        }
    }

    /// The more-alarming of two statuses, for the collapsed peek indicator.
    func worse(than other: NotchStatus) -> NotchStatus {
        severity >= other.severity ? self : other
    }
}

/// Design tokens for the island, kept in one place so the collapsed bar, the panel, and
/// every row share the exact same blacks, whites, and radii.
enum NotchTheme {
    /// Pure black for the notch-hugging surface — must match the physical bezel exactly.
    static let surface = Color.black

    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.6)
    static let tertiaryText = Color.white.opacity(0.38)
    static let hairline = Color.white.opacity(0.10)
    static let ringTrack = Color.white.opacity(0.14)
    /// Faint wash shown while the open-intent timer is charging, so a deliberate hover
    /// feels acknowledged before the panel actually springs open.
    static let intentWash = Color.white.opacity(0.06)

    static let collapsedBottomRadius: CGFloat = 10
    static let expandedBottomRadius: CGFloat = 22
    static let topRadius: CGFloat = 6
}
