import Testing
@testable import A11yBaselineCore

@Suite("Распределение бюджета обхода")
struct WalkPlannerTests {

    // MARK: - Вкладки

    @Test("Бюджета хватает и на ширину, и на глубину")
    func breadthAndDepth() {
        let plan = WalkPlanner.plan(tabs: ["Медиатека", "Коллекции", "Поиск"], cellCount: 0, budget: 10)
        // 10 − 1 стартовый = 9 переходов: 3 вкладки вширь, на глубину
        // остаётся 6, но вкладок всего 3.
        #expect(plan == .tabs(breadth: ["Медиатека", "Коллекции", "Поиск"],
                              depth: ["Медиатека", "Коллекции", "Поиск"]))
    }

    @Test("При нехватке бюджета жертвуем глубиной, а не шириной")
    func breadthWinsWhenTight() {
        let plan = WalkPlanner.plan(tabs: ["A", "B", "C", "D"], cellCount: 0, budget: 5)
        // 4 перехода уходят на четыре вкладки, на спуск не остаётся ничего.
        #expect(plan == .tabs(breadth: ["A", "B", "C", "D"], depth: []))
    }

    @Test("Вкладок больше, чем бюджета — лишние отбрасываем")
    func tabsTruncated() {
        let plan = WalkPlanner.plan(tabs: ["A", "B", "C", "D", "E"], cellCount: 0, budget: 3)
        #expect(plan == .tabs(breadth: ["A", "B"], depth: []))
    }

    @Test("Остаток бюджета уходит на глубину частично")
    func partialDepth() {
        let plan = WalkPlanner.plan(tabs: ["A", "B", "C"], cellCount: 0, budget: 5)
        // 4 перехода: 3 вкладки вширь, на глубину остаётся один.
        #expect(plan == .tabs(breadth: ["A", "B", "C"], depth: ["A"]))
    }

    // MARK: - Список

    @Test("Без вкладок идём по строкам списка")
    func listWalk() {
        let plan = WalkPlanner.plan(tabs: [], cellCount: 5, budget: 4)
        #expect(plan == .list(cellIndices: [0, 1, 2]))
    }

    @Test("Строк меньше, чем бюджета — берём сколько есть")
    func listShorterThanBudget() {
        let plan = WalkPlanner.plan(tabs: [], cellCount: 2, budget: 10)
        #expect(plan == .list(cellIndices: [0, 1]))
    }

    @Test("Пустой список даёт только стартовый экран")
    func emptyList() {
        #expect(WalkPlanner.plan(tabs: [], cellCount: 0, budget: 10) == .list(cellIndices: []))
    }

    // MARK: - Границы

    @Test("Бюджета хватает только на стартовый экран")
    func budgetOne() {
        #expect(WalkPlanner.plan(tabs: ["A"], cellCount: 9, budget: 1) == .tabs(breadth: [], depth: []))
        #expect(WalkPlanner.plan(tabs: [], cellCount: 9, budget: 1) == .list(cellIndices: []))
    }

    @Test("Нулевой и отрицательный бюджет не роняют планировщик")
    func nonPositiveBudget() {
        #expect(WalkPlanner.plan(tabs: ["A"], cellCount: 3, budget: 0) == .tabs(breadth: [], depth: []))
        #expect(WalkPlanner.plan(tabs: [], cellCount: 3, budget: -5) == .list(cellIndices: []))
    }

    @Test("Отрицательное число строк не роняет планировщик")
    func negativeCellCount() {
        #expect(WalkPlanner.plan(tabs: [], cellCount: -1, budget: 10) == .list(cellIndices: []))
    }
}
