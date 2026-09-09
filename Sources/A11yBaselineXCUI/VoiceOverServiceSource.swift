#if canImport(XCTest) && canImport(XCUIAutomation) && A11Y_VOICEOVER_API
import Foundation
import XCTest
import A11yBaselineCore

/// Источник реплик через настоящий VoiceOver.
///
/// Требует iOS 27 и сборки с флагом `A11Y_VOICEOVER_API`. Флаг нужен потому,
/// что `XCUIDevice.voiceOverService` отсутствует в SDK Xcode 26, и без флага
/// файл просто не компилируется. Как только Xcode 27 станет базовым, флаг
/// и вся эта условная компиляция убираются одним коммитом.
///
/// Ради чего это нужно: здесь `spoken` — не восстановленная строка, а то, что
/// система реально произнесла. Настоящий VoiceOver склеивает элементы, режет
/// длинные подписи и объявляет роли на языке пользователя, и ни одно из этих
/// поведений приближением не воспроизводится.
@available(iOS 27.0, macOS 27.0, *)
@MainActor
public final class VoiceOverServiceSource: SpeechSource {

    public let fidelity: CaptureFidelity = .voiceOverService

    private let device: XCUIDevice
    private let maxElementsPerScreen: Int

    /// - Parameter maxElementsPerScreen: страховка от зацикливания.
    ///   Обход идёт вперёд до возврата в уже виденное состояние, но экран
    ///   с бесконечной прокруткой такого состояния не даёт, поэтому нужен
    ///   жёсткий потолок.
    public init(device: XCUIDevice = .shared, maxElementsPerScreen: Int = 400) {
        self.device = device
        self.maxElementsPerScreen = maxElementsPerScreen
    }

    public func begin() throws {
        try device.voiceOverService.enable()
    }

    public func end() throws {
        try device.voiceOverService.disable()
    }

    public func captureScreen(named name: String) throws -> ScreenSnapshot {
        let service = device.voiceOverService
        var utterances: [Utterance] = []
        var seen = Set<String>()

        var current = try service.currentSpeech()
        var index = 0

        while index < maxElementsPerScreen {
            let spoken = current?.utterance ?? ""

            // Возврат к уже произнесённой реплике на той же позиции означает,
            // что фокус упёрся в конец и дальше не идёт.
            let fingerprint = "\(index):\(spoken)"
            if !spoken.isEmpty, seen.contains(fingerprint) { break }
            seen.insert(fingerprint)

            if !spoken.isEmpty {
                utterances.append(Utterance(index: index, spoken: spoken))
                index += 1
            }

            guard let next = try service.moveForward(), next.utterance != spoken else { break }
            current = next
        }

        return ScreenSnapshot(screen: name, utterances: utterances)
    }
}
#endif
