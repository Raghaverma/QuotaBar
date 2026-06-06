import Foundation

/// The app's version, read from the bundle's `CFBundleShortVersionString` with a
/// compile-time fallback for `swift run` (where there's no Info.plist).
enum AppVersion {
    static let current: String = {
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !v.isEmpty {
            return v
        }
        return "0.1.0"
    }()
}
