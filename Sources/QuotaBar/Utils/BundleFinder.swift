import Foundation

extension Bundle {
    /// A robust custom locator for the SwiftPM resource bundle.
    /// Bypasses the auto-generated `Bundle.module` accessor, which crashes on macOS
    /// app bundles because it only checks the bundle root rather than `Contents/Resources`.
    static var customModule: Bundle {
        // 1. Search in the main bundle's resource URL (standard macOS app layout: Contents/Resources)
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("StatsUsage_StatsUsage.bundle"),
           let bundle = Bundle(url: resourceURL) {
            return bundle
        }
        
        // 2. Search in the main bundle URL (root of the app or CLI)
        let mainBundlePath = Bundle.main.bundleURL.appendingPathComponent("StatsUsage_StatsUsage.bundle")
        if let bundle = Bundle(url: mainBundlePath) {
            return bundle
        }
        
        // 3. Search in the directory of the current executable (for command-line runs)
        if let exeURL = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("StatsUsage_StatsUsage.bundle"),
           let bundle = Bundle(url: exeURL) {
            return bundle
        }
        
        // 4. Scan all loaded bundles to find the resource bundle dynamically (useful for test runs)
        for bundle in Bundle.allBundles {
            if bundle.bundlePath.hasSuffix("StatsUsage_StatsUsage.bundle") {
                return bundle
            }
        }
        
        // 5. Final fallback to the SwiftPM auto-generated accessor
        return Bundle.module
    }
}
