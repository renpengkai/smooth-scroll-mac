// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SmoothScroll",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SmoothScroll",
            path: "Sources/SmoothScroll",
            swiftSettings: [
                // 体积优先; 热路径每帧只有几次浮点运算, -Osize 与 -O 手感无差别
                .unsafeFlags(["-Osize"], .when(configuration: .release)),
            ]
        ),
    ]
)
