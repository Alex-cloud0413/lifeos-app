// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dayline",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "DaylineCore", targets: ["DaylineCore"]), .executable(name: "lifeos", targets: ["DaylineCLI"]), .executable(name: "dayline", targets: ["DaylineCLI"])],
    targets: [
        .target(name: "DaylineCore"),
        .executableTarget(name: "DaylineCLI", dependencies: ["DaylineCore"]),
        .testTarget(name: "DaylineCoreTests", dependencies: ["DaylineCore"])
    ]
)
