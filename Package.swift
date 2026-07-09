// swift-tools-version: 5.9
// 룬 라이벌즈 — 스플렌더 변형 게임.
// 엔진은 Foundation 외 무의존 → 이 머신(iOS SDK 없음)에서도 `swift run`으로 검증 가능.
import PackageDescription

let package = Package(
    name: "RuneRivals",
    products: [
        .library(name: "RuneRivalsEngine", targets: ["RuneRivalsEngine"]),
        .executable(name: "RuneRivalsSim", targets: ["RuneRivalsSim"]),
    ],
    targets: [
        .target(name: "RuneRivalsEngine"),
        .executableTarget(
            name: "RuneRivalsSim",
            dependencies: ["RuneRivalsEngine"]
        ),
        .testTarget(
            name: "RuneRivalsEngineTests",
            dependencies: ["RuneRivalsEngine"]
        ),
    ]
)
