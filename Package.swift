// swift-tools-version: 6.0
import PackageDescription

// Пакет намеренно разделён на два таргета.
//
// A11yBaselineCore — чистая логика без XCTest и без UIKit: модель базовой линии,
// движок правил, диффер и отчёты. Отсюда следует три практических выигрыша:
// его можно покрыть обычными юнит-тестами, он собирается на Linux в CI
// (то есть проверка правил не требует macOS-раннера), и он переживает смену
// способа съёма речи — а способ меняется прямо сейчас, см. A11yBaselineXCUI.
//
// A11yBaselineXCUI — тонкий слой поверх XCUITest, который умеет только одно:
// пройти по приложению и отдать последовательность реплик. Вся оценка того,
// хороша реплика или плоха, живёт в Core и про XCUITest ничего не знает.
let package = Package(
    name: "A11yBaseline",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "A11yBaselineCore", targets: ["A11yBaselineCore"]),
        .library(name: "A11yBaselineXCUI", targets: ["A11yBaselineXCUI"]),
        .executable(name: "a11y-report", targets: ["a11y-report"]),
    ],
    targets: [
        .target(name: "A11yBaselineCore"),
        .target(name: "A11yBaselineXCUI", dependencies: ["A11yBaselineCore"]),
        .executableTarget(name: "a11y-report", dependencies: ["A11yBaselineCore"]),
        .testTarget(name: "A11yBaselineCoreTests", dependencies: ["A11yBaselineCore"]),
    ]
)
