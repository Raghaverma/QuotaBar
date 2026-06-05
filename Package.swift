// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatsUsage",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "StatsUsage", targets: ["StatsUsage"])
    ],
    targets: [
        .target(name: "StatsUsageDomain"),
        .target(name: "StatsUsageInfrastructure", dependencies: ["StatsUsageDomain"]),
        .target(name: "StatsUsageProviders", dependencies: ["StatsUsageDomain"]),
        .target(name: "StatsUsageApplication", dependencies: ["StatsUsageDomain"]),
        .target(name: "StatsUsagePresentation", dependencies: ["StatsUsageDomain"]),
        .target(name: "StatsUsageFeatures", dependencies: [
            "StatsUsageDomain", "StatsUsageApplication", "StatsUsagePresentation"
        ]),
        .target(name: "StatsUsageBootstrap", dependencies: [
            "StatsUsageDomain", "StatsUsageApplication",
            "StatsUsageFeatures", "StatsUsagePresentation"
        ]),
        .executableTarget(
            name: "StatsUsage",
            dependencies: [
                "StatsUsageDomain", "StatsUsageInfrastructure", "StatsUsageProviders",
                "StatsUsageApplication", "StatsUsagePresentation",
                "StatsUsageFeatures", "StatsUsageBootstrap"
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "StatsUsageTests",
            dependencies: [
                "StatsUsage", "StatsUsageDomain", "StatsUsageInfrastructure",
                "StatsUsageProviders", "StatsUsageApplication",
                "StatsUsagePresentation", "StatsUsageFeatures", "StatsUsageBootstrap"
            ],
            exclude: ["Fixtures"]
        )
    ]
)
