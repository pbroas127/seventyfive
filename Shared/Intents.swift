import AppIntents
import WidgetKit

/// Checks a task on or off from the Home Screen widget, then syncs it so your friend sees it live.
struct ToggleTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Check off a task"
    static var isDiscoverable = false

    @Parameter(title: "Task") var task: String

    init() {}
    init(task: String) { self.task = task }

    func perform() async throws -> some IntentResult {
        let day = HardStore.load().currentDay()
        _ = HardActions.apply { $0.toggle(task, day: day) }
        try? await Sync.push()
        return .result()
    }
}
