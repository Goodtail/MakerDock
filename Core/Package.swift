// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PlateShelfCore",
    defaultLocalization: "ko",
    platforms: [.macOS(.v13)],
    products: [.library(name: "PlateShelfCore", targets: ["PlateShelfCore"])],
    dependencies: [.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")],
    targets: [
        .target(name: "PlateShelfCore", dependencies: ["ZIPFoundation"], resources: [.process("Resources")]),
        .testTarget(name: "PlateShelfCoreTests", dependencies: ["PlateShelfCore", "ZIPFoundation"])
    ]
)
