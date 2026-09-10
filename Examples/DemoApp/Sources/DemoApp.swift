import SwiftUI

/// Демонстрационное приложение с НАМЕРЕННЫМИ дефектами доступности.
///
/// Каждый экран воспроизводит дефекты, которые ловит соответствующее правило.
/// Это не игрушка: на нём измеряется, сколько находок движок даёт на реальном
/// прогоне через симулятор и нет ли среди них ложных. Без такого прогона
/// правила остаются теорией, проверенной только на фикстурах.
@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Каталог")
                .font(.largeTitle)

            // ДЕФЕКТ 1 — иконочная кнопка без явной подписи.
            // Ожидается: symbol-derived-label. Именно так это выглядит
            // в реальности: SwiftUI подставит имя символа, и VoiceOver
            // произнесёт «Send» в русском приложении. Правило пустой подписи
            // здесь не срабатывает, потому что подпись формально есть —
            // это выяснилось живым прогоном, а не на фикстурах.
            Button(action: {}) {
                Image(systemName: "paperplane")
            }
            .accessibilityIdentifier("send")

            // ДЕФЕКТ 2 — подпись-заглушка вместо назначения.
            // Ожидается: generic-label.
            Button("Кнопка") {}
                .accessibilityIdentifier("generic")

            // ДЕФЕКТ 3 — в подпись утекло имя ресурса.
            // Ожидается: filename-label.
            Button(action: {}) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("ic_close_24")
            .accessibilityIdentifier("close")

            // ДЕФЕКТ 4 — три элемента звучат одинаково.
            // Ожидается: ровно ОДНА находка duplicate-label на всю группу.
            ForEach(0..<3, id: \.self) { index in
                Button("Подробнее") {}
                    .accessibilityIdentifier("more-\(index)")
            }

            // ДЕФЕКТ 5 — на кнопке видно «Далее», озвучивается «Продолжить».
            // Ломает управление голосом. Ожидается: label-in-name.
            Button(action: {}) {
                Text("Далее")
            }
            .accessibilityLabel("Продолжить")
            .accessibilityIdentifier("next")

            // ДЕФЕКТ 6 — цель нажатия 20×20 пт при минимуме 24 по стандарту.
            // Ожидается: находка ВСТРОЕННОГО аудита Apple («Hit area is too
            // small»), а не нашего правила. XCUITest отдаёт для SwiftUI-кнопки
            // границы содержимого, а не область нажатия, поэтому меряет размер
            // цели тот, у кого есть настоящая геометрия.
            Button(action: {}) {
                Image(systemName: "trash")
                    .frame(width: 20, height: 20)
            }
            .frame(width: 20, height: 20)
            .accessibilityLabel("Удалить")
            .accessibilityIdentifier("delete")

            // КОНТРОЛЬНЫЙ ЭЛЕМЕНТ — сделан правильно.
            // Ожидается: НИ ОДНОЙ находки. Если правила его тронут,
            // значит движок шумит, и это важнее любого пропуска.
            Button("Сохранить черновик") {}
                .frame(minWidth: 120, minHeight: 44)
                .accessibilityIdentifier("save")
        }
        .padding()
    }
}
