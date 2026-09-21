// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InputMethodPrompt",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "InputMethodPrompt", targets: ["InputMethodPrompt"])],
    targets: [
        .executableTarget(name: "InputMethodPrompt", linkerSettings: [.linkedFramework("Carbon")])
    ]
)
