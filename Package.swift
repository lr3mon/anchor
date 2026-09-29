// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "anchor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "anchor", targets: ["Anchor"])
    ],
    targets: [
        // 로직은 library 로 분리한다. executableTarget 은 @testable import 가
        // 되지 않아 테스트를 붙일 수 없으므로, 같은 소스를 쓰는 core 타깃을 둔다.
        .target(
            name: "AnchorCore",
            path: "Sources/AnchorCore"
        ),
        // 진입점 + 명령 디스패치만 담당하는 얇은 실행 타깃.
        .executableTarget(
            name: "Anchor",
            dependencies: ["AnchorCore"],
            path: "Sources/Anchor"
        ),
        .testTarget(
            name: "AnchorTests",
            dependencies: ["AnchorCore"],
            path: "Tests/AnchorTests"
        )
    ]
)
