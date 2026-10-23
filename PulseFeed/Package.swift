// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PulseFeed",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Database
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0"),
        // GRDBQuery: commented out of targets; #Preview macros fail with `swift build`.
        // Re-enable when migrating to Xcode project.
        // .package(url: "https://github.com/groue/GRDBQuery.git", from: "0.11.0"),

        // RSS Parsing
        .package(url: "https://github.com/nmdias/FeedKit.git", exact: "10.4.0"), // pinned 2026-10-20 on the rebuild: FeedKit newer than 10.4.0 adds Feed.rdf, which normalize() does not handle; the old Package.resolved no longer resolves under Swift 6.4

        // HTML Parsing
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.11.0"),

        // Claude API
        .package(url: "https://github.com/jamesrochabrun/SwiftAnthropic.git", from: "2.1.0"),

        // Menu Bar
        .package(url: "https://github.com/orchetect/MenuBarExtraAccess.git", from: "1.0.0"),

        // Launch at Login
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern.git", from: "1.0.0"),

        // Auto-updates
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.8.0"),
    ],
    targets: [
        .executableTarget(
            name: "PulseFeed",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                // GRDBQuery: #Preview macros in 0.11.0 fail with `swift build` CLI.
                // Builds fine in Xcode. Re-enable when migrating to Xcode project.
                // .product(name: "GRDBQuery", package: "GRDBQuery"),
                "FeedKit",
                "SwiftSoup",
                "SwiftAnthropic",
                "MenuBarExtraAccess",
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
                "Sparkle",
            ],
            path: "PulseFeed",
            exclude: ["Resources"]
        ),
        // Smoke tests for the executable target.
        // SwiftPM (swift-tools 6.0) supports `@testable import` of an executable
        // target even though it declares `@main` — verified building/running on
        // Xcode's Swift 6.4 toolchain. No library extraction needed.
        .testTarget(
            name: "PulseFeedTests",
            dependencies: ["PulseFeed"],
            path: "Tests/PulseFeedTests"
        ),
    ]
)
