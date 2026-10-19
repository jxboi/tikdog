// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TikDogCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "TikDogCore", targets: ["TikDogCore"])],
    targets: [.target(name: "TikDogCore"), .testTarget(name: "TikDogCoreTests", dependencies: ["TikDogCore"])]
)
