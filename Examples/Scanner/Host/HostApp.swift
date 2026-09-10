import SwiftUI

/// Приложение-носитель для сканера. Ничего не делает и не должно:
/// XCUITest требует цель-хост, а сканируем мы чужое приложение
/// по идентификатору.
@main
struct ScannerHostApp: App {
    var body: some Scene {
        WindowGroup {
            Text("A11y Scanner")
                .accessibilityHidden(true)
        }
    }
}
