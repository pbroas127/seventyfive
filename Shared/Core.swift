import Foundation
import SwiftUI
import UserNotifications
import WidgetKit

enum Hard {
    static let group = "group.com.peterbroas.seventyfive"
    static let container = "iCloud.com.peterbroas.seventyfive"
    static let days = 75
    static let inviteBase = "https://seventyfive-hard.vercel.app/add"
}

struct HardTask: Identifiable, Hashable {
    let id: String
    let title: String
    let short: String
    let icon: String
    let phrase: String   // how a sentence names it, like "your outdoor workout"

    static let all: [HardTask] = [
        .init(id: "workout", title: "45 minute workout", short: "Workout", icon: "figure.strengthtraining.traditional", phrase: "your workout"),
        .init(id: "outdoor", title: "45 minute outdoor workout", short: "Outdoor workout", icon: "sun.max.fill", phrase: "your outdoor workout"),
        .init(id: "bible", title: "Read the Bible", short: "Bible", icon: "book.closed.fill", phrase: "your Bible reading"),
        .init(id: "reading", title: "Read 10 pages", short: "Reading", icon: "books.vertical.fill", phrase: "your 10 pages"),
        .init(id: "water", title: "Drink one gallon of water", short: "Water", icon: "drop.fill", phrase: "your gallon of water"),
        .init(id: "diet", title: "Follow your diet", short: "Diet", icon: "fork.knife", phrase: "your diet"),
        .init(id: "clean", title: "No cheat meals or alcohol", short: "No cheats", icon: "nosign", phrase: "no cheat meals or alcohol"),
    ]
}

// MARK: - Stored state

struct DayRecord: Codable, Equatable {
    var done: Set<String> = []
    var note = ""
    var hasPhoto = false
    var food: [FoodEntry] = []
    var waterOz = 0
    var foodShared = true    // a friend's own choice, read from their record
    var goals: [Int]?        // a friend's calorie, protein, water goals

    var count: Int { HardTask.all.filter { done.contains($0.id) }.count }
    var complete: Bool { count == HardTask.all.count }
    var kcal: Int { food.reduce(0) { $0 + $1.kcal } }
    var protein: Int { Int(food.reduce(0) { $0 + $1.protein }.rounded()) }

    init(done: Set<String> = [], note: String = "", hasPhoto: Bool = false) {
        self.done = done; self.note = note; self.hasPhoto = hasPhoto
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        done = (try? c.decodeIfPresent(Set<String>.self, forKey: .done)) ?? []
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        hasPhoto = (try? c.decodeIfPresent(Bool.self, forKey: .hasPhoto)) ?? false
        food = (try? c.decodeIfPresent([FoodEntry].self, forKey: .food)) ?? []
        waterOz = (try? c.decodeIfPresent(Int.self, forKey: .waterOz)) ?? 0
        foodShared = (try? c.decodeIfPresent(Bool.self, forKey: .foodShared)) ?? true
    }
}

struct Reminder: Codable, Equatable {
    var on: Bool
    var minutes: Int
}

struct AppSettings: Codable, Equatable {
    var appearance = 1 // 0 system, 1 dark, 2 light
    var accent = Accent.ember.rawValue
    var dayEnd = 23 * 60 + 59
    var notifications = true
    var reminders: [String: Reminder] = AppSettings.defaultReminders
    var nudges: [Int] = AppSettings.defaultNudges
    var version = AppSettings.currentVersion
    var calorieGoal = 2000
    var proteinGoal = 150
    var waterGoal = 128      // ounces, one gallon
    var shareFood = true

    /// Task reminders start empty; the user turns on the ones they want.
    static let defaultReminders: [String: Reminder] = [
        "workout": .init(on: false, minutes: 8 * 60),
        "outdoor": .init(on: false, minutes: 10 * 60),
        "bible": .init(on: false, minutes: 7 * 60),
        "reading": .init(on: false, minutes: 21 * 60),
        "water": .init(on: false, minutes: 13 * 60),
        "diet": .init(on: false, minutes: 12 * 60),
        "clean": .init(on: false, minutes: 19 * 60),
    ]
    /// One morning, one afternoon, one night.
    static let defaultNudges = [9 * 60, 15 * 60, 23 * 60]
    static let currentVersion = 2

    init() {}
    // Tolerant decoding so a new setting never wipes the old ones.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let base = AppSettings()
        appearance = (try? c.decodeIfPresent(Int.self, forKey: .appearance)) ?? base.appearance
        accent = (try? c.decodeIfPresent(String.self, forKey: .accent)) ?? base.accent
        dayEnd = (try? c.decodeIfPresent(Int.self, forKey: .dayEnd)) ?? base.dayEnd
        notifications = (try? c.decodeIfPresent(Bool.self, forKey: .notifications)) ?? base.notifications
        reminders = (try? c.decodeIfPresent([String: Reminder].self, forKey: .reminders)) ?? base.reminders
        nudges = (try? c.decodeIfPresent([Int].self, forKey: .nudges)) ?? base.nudges
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        calorieGoal = (try? c.decodeIfPresent(Int.self, forKey: .calorieGoal)) ?? base.calorieGoal
        proteinGoal = (try? c.decodeIfPresent(Int.self, forKey: .proteinGoal)) ?? base.proteinGoal
        waterGoal = (try? c.decodeIfPresent(Int.self, forKey: .waterGoal)) ?? base.waterGoal
        shareFood = (try? c.decodeIfPresent(Bool.self, forKey: .shareFood)) ?? base.shareFood
        // Build 1 shipped with two task reminders on and three evening nudges. Reset those once.
        if version < 2 {
            reminders = AppSettings.defaultReminders
            nudges = AppSettings.defaultNudges
            version = AppSettings.currentVersion
        }
    }
}

struct HardState: Codable, Equatable {
    var firstName = ""
    var lastName = ""
    var signedIn = false
    var myCode = ""          // CloudKit user record name, also the friend code
    var attemptID = UUID().uuidString
    var startKey = ""        // yyyy-MM-dd of day one
    var days: [String: DayRecord] = [:]
    var dirtyDays: Set<Int> = []
    var profileDirty = true
    var friendCode = ""
    var dismissedMiss = ""
    var settings = AppSettings()
    var favorites: [FoodEntry] = []

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let b = HardState()
        firstName = (try? c.decodeIfPresent(String.self, forKey: .firstName)) ?? b.firstName
        lastName = (try? c.decodeIfPresent(String.self, forKey: .lastName)) ?? b.lastName
        signedIn = (try? c.decodeIfPresent(Bool.self, forKey: .signedIn)) ?? b.signedIn
        myCode = (try? c.decodeIfPresent(String.self, forKey: .myCode)) ?? b.myCode
        attemptID = (try? c.decodeIfPresent(String.self, forKey: .attemptID)) ?? b.attemptID
        startKey = (try? c.decodeIfPresent(String.self, forKey: .startKey)) ?? b.startKey
        days = (try? c.decodeIfPresent([String: DayRecord].self, forKey: .days)) ?? b.days
        dirtyDays = (try? c.decodeIfPresent(Set<Int>.self, forKey: .dirtyDays)) ?? b.dirtyDays
        profileDirty = (try? c.decodeIfPresent(Bool.self, forKey: .profileDirty)) ?? b.profileDirty
        friendCode = (try? c.decodeIfPresent(String.self, forKey: .friendCode)) ?? b.friendCode
        dismissedMiss = (try? c.decodeIfPresent(String.self, forKey: .dismissedMiss)) ?? b.dismissedMiss
        settings = (try? c.decodeIfPresent(AppSettings.self, forKey: .settings)) ?? b.settings
        favorites = (try? c.decodeIfPresent([FoodEntry].self, forKey: .favorites)) ?? b.favorites
    }

    func day(_ n: Int) -> DayRecord { days[String(n)] ?? DayRecord() }
    var intDays: [Int: DayRecord] { Dictionary(uniqueKeysWithValues: days.compactMap { k, v in Int(k).map { ($0, v) } }) }

    /// Day number right now, clamped to 1...75.
    func currentDay(_ now: Date = .now) -> Int {
        min(max(DayMath.number(startKey: startKey, now: now, dayEnd: settings.dayEnd), 1), Hard.days)
    }

    mutating func toggle(_ task: String, day: Int) {
        var r = self.day(day)
        if r.done.contains(task) { r.done.remove(task) } else { r.done.insert(task) }
        days[String(day)] = r
        dirtyDays.insert(day)
    }

    /// Adds (or with a negative number removes) water. Reaching the goal checks the task off.
    /// Returns true when this change is what completed the gallon.
    @discardableResult
    mutating func addWater(_ oz: Int, day n: Int) -> Bool {
        var reached = false
        editDay(n) {
            let before = $0.waterOz
            $0.waterOz = max(0, $0.waterOz + oz)
            if before < settings.waterGoal, $0.waterOz >= settings.waterGoal, !$0.done.contains("water") {
                $0.done.insert("water")
                reached = true
            }
        }
        return reached
    }

    /// Foods eaten in the last two weeks, newest first, one per name.
    var recentFoods: [FoodEntry] {
        var seen = Set<String>()
        var out: [FoodEntry] = []
        for n in intDays.keys.sorted(by: >).prefix(14) {
            for e in day(n).food.reversed() where seen.insert(e.name.lowercased()).inserted { out.append(e) }
        }
        return out
    }

    mutating func editDay(_ n: Int, _ f: (inout DayRecord) -> Void) {
        var r = day(n)
        f(&r)
        days[String(n)] = r
        dirtyDays.insert(n)
    }
}

// MARK: - Days

enum DayMath {
    static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ d: Date) -> String { fmt.string(from: d) }
    static func date(_ key: String) -> Date? { fmt.date(from: key) }

    /// The calendar day the user is living in. A day end after midnight (say 1:00) keeps late night on the previous day.
    static func logicalToday(_ now: Date = .now, dayEnd: Int) -> Date {
        let shifted = dayEnd < 12 * 60 ? now.addingTimeInterval(-Double(dayEnd + 1) * 60) : now
        return Calendar.current.startOfDay(for: shifted)
    }

    static func number(startKey: String, now: Date = .now, dayEnd: Int) -> Int {
        guard let start = date(startKey) else { return 1 }
        let cal = Calendar.current
        return (cal.dateComponents([.day], from: cal.startOfDay(for: start), to: logicalToday(now, dayEnd: dayEnd)).day ?? 0) + 1
    }

    static func date(day n: Int, startKey: String) -> Date {
        Calendar.current.date(byAdding: .day, value: n - 1, to: date(startKey) ?? .now) ?? .now
    }

    static func nextRollover(after now: Date, dayEnd: Int) -> Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: logicalToday(now, dayEnd: dayEnd)) ?? now
        return dayEnd < 12 * 60 ? tomorrow.addingTimeInterval(Double(dayEnd + 1) * 60) : tomorrow
    }

    /// When the given logical day ends.
    static func dayEndDate(for day: Date, dayEnd: Int) -> Date {
        let next = dayEnd < 12 * 60 ? Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day : day
        return next.addingTimeInterval(Double(dayEnd + 1) * 60)
    }

    static func time(_ minutes: Int) -> String {
        var c = DateComponents(); c.hour = minutes / 60; c.minute = minutes % 60
        return (Calendar.current.date(from: c) ?? .now).formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Storage (shared with the widget through the app group)

enum HardStore {
    static let defaults = UserDefaults(suiteName: Hard.group) ?? .standard

    static func load() -> HardState {
        guard let data = defaults.data(forKey: "state"), let s = try? JSONDecoder().decode(HardState.self, from: data) else { return HardState() }
        return s
    }

    static func save(_ s: HardState) {
        defaults.set(try? JSONEncoder().encode(s), forKey: "state")
    }

    static var folder: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Hard.group) ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// owner is "me" for your own photos, or the friend's code for cached copies of theirs.
    static func photoURL(owner: String, attempt: String, day: Int) -> URL {
        folder.appendingPathComponent("\(owner)_\(attempt)_\(day).jpg")
    }

    static var avatarURL: URL { folder.appendingPathComponent("avatar.jpg") }
}

/// Changes the widget and the app both make, so they stay identical.
enum HardActions {
    static func apply(_ f: (inout HardState) -> Void) -> HardState {
        var s = HardStore.load()
        f(&s)
        HardStore.save(s)
        Reminders.reschedule(s)
        WidgetCenter.shared.reloadAllTimelines()
        return s
    }
}

// MARK: - Words

enum Phrases {
    static let reminder: [String: [String]] = [
        "workout": ["Time to lift 💪 Your 45 minute workout is waiting.", "Workout one. Go get it 🏋️", "Nobody is coming to do this for you. Workout time.", "Sweat now, smile later 😤", "Clock in. 45 minutes. Let's go 🔥"],
        "outdoor": ["Get outside ☀️ 45 minutes, rain or shine.", "Fresh air workout time 🌳", "Outdoor workout. Weather is not an excuse 🌧️", "Lace up and step outside 👟", "The sky is your gym today 🌤️"],
        "bible": ["Time in the Word 📖", "Open your Bible and slow down for a minute 🙏", "Daily bread 🍞 Read your Bible today.", "Be still and read 📖", "A few minutes with God before the day gets loud 🙏"],
        "reading": ["10 pages today 📚", "Grab your book. Ten pages.", "Readers are leaders 📚 Ten pages to go.", "Ten pages. Done before your coffee cools ☕", "Book time 📖"],
        "water": ["Drink up 💧 A gallon does not drink itself.", "Hydration check 💧", "Refill that bottle 🚰", "Keep chasing that gallon 💧", "Water break. Right now 💧"],
        "diet": ["Stick to the plan 🥗", "Eat like you mean it 🍽️", "Your diet is a promise to yourself 🥦", "Plan the next meal, then follow it 🥗", "Fuel, not filler 🍳"],
        "clean": ["No cheat meals. No alcohol. No exceptions 🚫", "Say no to the cheat meal 🙅", "Stay clean today 🧊", "Future you says thanks for skipping it 🚫🍺", "Hold the line 🛡️"],
    ]

    static let done = ["One more down.", "Keep stacking.", "That is how it is done.", "Discipline looks good on you.", "Nice work.", "Check.", "Easy. Next."]
    static let complete = ["Day {d} is in the books.", "Seven for seven.", "Another day stacked.", "You kept your word today.", "Nothing left on the list. Rest up."]

    static func fill(_ s: String, n: Int = 0, d: Int = 0) -> String {
        s.replacingOccurrences(of: "{n}", with: n == 1 ? "1 task" : "\(n) tasks").replacingOccurrences(of: "{d}", with: "\(d)")
    }
}

// MARK: - Reminders

enum Reminders {
    /// Rebooks five days of local notifications. Called after every change, so today's reminders
    /// skip anything already checked off and the end of day nudges stop once all seven are done.
    static func reschedule(_ s: HardState) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard s.settings.notifications, s.signedIn, !s.startKey.isEmpty else { return }
        let now = Date.now
        let cal = Calendar.current
        let today = DayMath.logicalToday(now, dayEnd: s.settings.dayEnd)

        for offset in 0..<5 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let n = DayMath.number(startKey: s.startKey, now: day.addingTimeInterval(12 * 3600), dayEnd: 23 * 60 + 59)
            guard (1...Hard.days).contains(n) else { continue }
            let record = offset == 0 ? s.day(n) : DayRecord()

            func fire(_ minutes: Int) -> Date? {
                var date = day.addingTimeInterval(Double(minutes) * 60)
                // With a day end after midnight, times before it belong to the next calendar night.
                if s.settings.dayEnd < 12 * 60, minutes <= s.settings.dayEnd { date = date.addingTimeInterval(86400) }
                return date > now ? date : nil
            }

            for task in HardTask.all {
                guard let r = s.settings.reminders[task.id], r.on, !record.done.contains(task.id), let at = fire(r.minutes) else { continue }
                add(center, id: "task.\(task.id).\(n)", title: task.title, body: Phrases.reminder[task.id]?.randomElement() ?? task.title, at: at, day: n)
            }

            var congratulated = false
            for m in s.settings.nudges.sorted() {
                guard let at = fire(m) else { continue }
                if record.complete {
                    // One pat on the back at the next nudge, then quiet until tomorrow.
                    guard !congratulated else { continue }
                    congratulated = true
                }
                let hoursLeft = max(0, Int(DayMath.dayEndDate(for: day, dayEnd: s.settings.dayEnd).timeIntervalSince(at) / 3600))
                let text = Nudges.text(minutes: m, record: record, day: n, hoursLeft: hoursLeft, calorieGoal: s.settings.calorieGoal)
                add(center, id: "nudge.\(m).\(n)", title: text.title, body: text.body, at: at, day: n)
            }
        }
    }

    private static func add(_ center: UNUserNotificationCenter, id: String, title: String, body: String, at: Date, day: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "day\(day)"
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: at)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }
}

// MARK: - Nudge words

enum DayPart {
    case morning, afternoon, evening, night

    init(minutes m: Int) {
        switch m {
        case 4 * 60 ..< 12 * 60: self = .morning
        case 12 * 60 ..< 17 * 60: self = .afternoon
        case 17 * 60 ..< 21 * 60: self = .evening
        default: self = .night
        }
    }

    var icon: String {
        switch self {
        case .morning: "sunrise.fill"
        case .afternoon: "sun.max.fill"
        case .evening: "sunset.fill"
        case .night: "moon.stars.fill"
        }
    }

    var name: String {
        switch self {
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        case .night: "Night"
        }
    }
}

/// End of day nudges written from the time of day and what is already checked off.
enum Nudges {
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", and " + items.last!
        }
    }

    static func text(minutes: Int, record: DayRecord, day: Int, hoursLeft: Int, calorieGoal: Int = 0) -> (title: String, body: String) {
        let part = DayPart(minutes: minutes)
        let left = HardTask.all.filter { !record.done.contains($0.id) }
        let done = HardTask.all.filter { record.done.contains($0.id) }
        let leftText = list(left.map(\.phrase))
        let doneText = list(done.map(\.phrase))
        let k = done.count
        let n = left.count
        let first = left.first?.phrase ?? ""
        let hours = hoursLeft <= 1 ? "about an hour" : "\(hoursLeft) hours"
        let title = "Day \(day)"

        if n == 0 {
            return (title, [
                "All seven done. Great job, see you tomorrow ✅",
                "Day \(day) is in the books. Rest up, see you tomorrow 💪",
                "Nothing left on the list. That is how it is done 🔥",
            ].randomElement()!)
        }

        let pool: [String]
        let calsLeft = calorieGoal - record.kcal
        let foodLine: [String] = record.food.isEmpty || calorieGoal == 0 || record.done.contains("diet") ? [] :
            calsLeft >= 0 ? ["\(calsLeft) calories left today 🍽️ Still to do: \(leftText)."] : ["You are \(-calsLeft) calories over today. Still to do: \(leftText)."]
        switch part {
        case .morning:
            pool = k == 0 ? [
                "Good morning ☀️ Day \(day) starts now. Seven to go, let's get started.",
                "Rise and grind ☀️ Nothing checked yet. Start with \(first).",
                "Good morning. Clean slate today, all seven waiting. Let's go 💪",
            ] : [
                "Good morning ☀️ You already have \(k) done. Keep it going.",
                "Early start 🔥 \(doneText) done already. \(n) to go.",
                "Good morning. \(k) down, \(n) to go. Next up: \(first).",
            ]
        case .afternoon:
            var p = k == 0 ? [
                "Half the day is gone and nothing is checked yet ⏳ Start with \(first).",
                "Afternoon check in. All seven still open. Time to move 🏃",
            ] : [
                "Afternoon check in ☀️ \(doneText) done. Still left: \(leftText).",
                "Nice work so far. \(k) done, \(n) to go. Next: \(first).",
                "Good pace 👊 Still need \(leftText).",
            ]
            if left.contains(where: { $0.id == "diet" }) { p.append("Lunch time 🥗 Stick to your diet. Still left: \(leftText).") }
            if left.contains(where: { $0.id == "water" }) { p.append("Refill that bottle 💧 Still left: \(leftText).") }
            pool = p + foodLine
        case .evening:
            pool = n <= 2 ? [
                "Almost there 🔥 Just \(leftText) left.",
                "So close. Finish \(leftText) and day \(day) is done 💪",
            ] : [
                "Evening check in 🌆 \(n) left: \(leftText).",
                "Knock these out before it gets late: \(leftText) ⏳",
                "\(k) done, \(n) to go. Get \(first) out of the way next.",
            ] + foodLine
        case .night:
            pool = [
                "It's getting late 🌙 Only \(hours) left and you still need \(leftText).",
                "Really? \(hours) left and \(n) still open 👀 \(leftText.prefix(1).uppercased() + leftText.dropFirst()).",
                "Last call ⏰ Finish \(leftText) before day \(day) ends.",
                "Do not let day \(day) slip away 🚨 Still need \(leftText).",
            ]
        }
        return (title, pool.randomElement()!)
    }
}
