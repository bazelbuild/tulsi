// swift-tools-version:4.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Tulsi",
    products: [
        .library(
            name: "TulsiGenerator",
            type: .static,
            targets: ["TulsiGenerator"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "TulsiGenerator",
            dependencies: [],
            path: "src/TulsiGenerator")
    ],
    swiftLanguageVersions: [4]
)
