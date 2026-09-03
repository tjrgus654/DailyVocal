// swift-tools-version:5.9
//
// Windows/macOS 공용 유닛테스트 전용 패키지.
// 앱 타깃은 이 패키지와 무관하게 Xcode 프로젝트로 구성한다
// (Core/Logic/*.swift 는 양쪽에서 동일 소스로 컴파일됨).
import PackageDescription

let package = Package(
    name: "VocalLogic",
    targets: [
        .target(name: "VocalLogic", path: "Core/Logic"),
        .testTarget(
            name: "VocalLogicTests",
            dependencies: ["VocalLogic"],
            path: "Tests/VocalLogicTests"
        )
    ]
)
