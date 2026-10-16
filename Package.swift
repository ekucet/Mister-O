// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MisterO",
    // macOS yalnızca MisterOCore testlerini `swift test` ile Mac'te koşabilmek için var;
    // SDK'nın kendisi iOS'ta çalışır.
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "MisterO", targets: ["MisterO"]),
    ],
    targets: [
        // Platformdan bağımsız: komut modeli, parser, runner motoru, sürücü protokolü.
        .target(name: "MisterOCore"),
        // UIKit/SwiftUI katmanı: view resolver, action executor, test paneli.
        .target(name: "MisterO", dependencies: ["MisterOCore"]),
        .testTarget(name: "MisterOCoreTests", dependencies: ["MisterOCore"]),
        .testTarget(name: "MisterOTests", dependencies: ["MisterO"]),
    ]
)
