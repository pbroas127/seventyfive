import WidgetKit
import SwiftUI
import AppIntents

struct HardEntry: TimelineEntry {
    let date: Date
    let state: HardState
    var day: Int { state.currentDay(date) }
    var record: DayRecord { state.day(day) }
    var accent: Accent { Accent.from(state) }
    var ready: Bool { state.signedIn && !state.startKey.isEmpty }
    var waiting: Int { max(0, 1 - DayMath.number(startKey: state.startKey, now: date, dayEnd: state.settings.dayEnd)) }
}

struct HardProvider: TimelineProvider {
    func placeholder(in context: Context) -> HardEntry {
        var s = HardState()
        s.signedIn = true
        s.startKey = DayMath.key(.now)
        s.days["1"] = DayRecord(done: ["workout", "bible", "water"])
        return HardEntry(date: .now, state: s)
    }

    func getSnapshot(in context: Context, completion: @escaping (HardEntry) -> Void) {
        let s = HardStore.load()
        completion(s.startKey.isEmpty ? placeholder(in: context) : HardEntry(date: .now, state: s))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HardEntry>) -> Void) {
        let s = HardStore.load()
        let next = DayMath.nextRollover(after: .now, dayEnd: s.settings.dayEnd)
        completion(Timeline(entries: [HardEntry(date: .now, state: s), HardEntry(date: next, state: s)], policy: .after(next)))
    }
}

struct HardWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HardEntry

    var body: some View {
        Group {
            if entry.ready && entry.waiting > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    if family != .accessoryRectangular && family != .accessoryCircular {
                        LogoMark(size: 18, accent: entry.accent, word: false)
                        Spacer()
                    }
                    Text(entry.waiting == 1 ? "1 DAY" : "\(entry.waiting) DAYS")
                        .font(.system(size: family == .accessoryCircular ? 16 : 34, weight: .black)).italic().fontWidth(.condensed)
                        .minimumScaleFactor(0.5)
                    Text("until day one").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else if !entry.ready {
                VStack(alignment: .leading, spacing: 8) {
                    LogoMark(size: 22, accent: entry.accent)
                    Spacer()
                    Text("Open the app to start day one").font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                switch family {
                case .systemSmall: small
                case .systemMedium: medium
                case .accessoryRectangular: rectangular
                case .accessoryCircular: circular
                default: large
                }
            }
        }
        .containerBackground(for: .widget) { Theme.bg }
        .widgetURL(URL(string: "seventyfive://today"))
    }

    private var dayTitle: some View {
        Text("DAY \(entry.day)")
            .font(.system(size: family == .systemLarge ? 44 : 34, weight: .black))
            .italic()
            .fontWidth(.condensed)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(Theme.text)
    }

    private var dateLine: some View {
        Text(entry.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.muted)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            LogoMark(size: 18, accent: entry.accent, word: false)
            Spacer()
            dayTitle
            dateLine
            Spacer()
            HStack(spacing: 3) {
                ForEach(0..<HardTask.all.count, id: \.self) { i in
                    Capsule().fill(i < entry.record.count ? entry.accent.color : Theme.raised).frame(height: 5)
                }
            }
            Text(entry.record.complete ? "All complete" : "\(entry.record.count) of \(HardTask.all.count)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(entry.record.complete ? entry.accent.color : Theme.muted)
                .padding(.top, 6)
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                LogoMark(size: 18, accent: entry.accent, word: false)
                Spacer()
                dayTitle
                dateLine
                Text(entry.record.complete ? "All complete" : "\(entry.record.count) of \(HardTask.all.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(entry.record.complete ? entry.accent.color : Theme.muted)
                    .padding(.top, 4)
            }
            .frame(width: 104, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                ForEach(HardTask.all) { task in
                    row(task, compact: true)
                }
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                dayTitle
                Spacer()
                LogoMark(size: 20, accent: entry.accent, word: false)
            }
            HStack {
                dateLine
                Spacer()
                Text(entry.record.complete ? "All complete" : "\(entry.record.count) of \(HardTask.all.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(entry.record.complete ? entry.accent.color : Theme.muted)
            }
            .padding(.bottom, 10)
            VStack(spacing: 6) {
                ForEach(HardTask.all) { task in
                    row(task, compact: false)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func row(_ task: HardTask, compact: Bool) -> some View {
        let done = entry.record.done.contains(task.id)
        return Button(intent: ToggleTaskIntent(task: task.id)) {
            HStack(spacing: compact ? 7 : 12) {
                ZStack {
                    Circle().strokeBorder(Theme.muted.opacity(0.5), lineWidth: 1.5)
                    if done {
                        Circle().fill(entry.accent.color)
                        Image(systemName: "checkmark")
                            .font(.system(size: compact ? 7 : 10, weight: .black))
                            .foregroundStyle(entry.accent.ink)
                    }
                }
                .frame(width: compact ? 14 : 22, height: compact ? 14 : 22)
                Text(compact ? task.short : task.title)
                    .font(.system(size: compact ? 12 : 15, weight: .semibold))
                    .strikethrough(done, color: Theme.muted)
                    .foregroundStyle(done ? Theme.muted : Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !compact, let extra = extra(task) {
                    Text(extra).font(.system(size: 12, weight: .bold)).monospacedDigit().foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 16 : 34)
            .padding(.horizontal, compact ? 0 : 12)
            .background {
                if !compact {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func extra(_ task: HardTask) -> String? {
        let r = entry.record
        switch task.id {
        case "water": return r.waterOz > 0 ? "\(r.waterOz) oz" : nil
        case "diet": return r.kcal > 0 ? "\(r.kcal) cal" : nil
        default: return nil
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DAY \(entry.day)")
                .font(.system(size: 20, weight: .black)).italic().fontWidth(.condensed)
            Text(entry.record.complete ? "All complete" : "\(entry.record.count) of \(HardTask.all.count) done")
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 2) {
                ForEach(0..<HardTask.all.count, id: \.self) { i in
                    Capsule().fill(i < entry.record.count ? Color.primary : Color.primary.opacity(0.25)).frame(height: 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var circular: some View {
        Gauge(value: Double(entry.record.count), in: 0...Double(HardTask.all.count)) {
            Text("DAY")
        } currentValueLabel: {
            Text("\(entry.day)").font(.system(size: 18, weight: .black)).fontWidth(.condensed)
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}

struct HardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HardToday", provider: HardProvider()) { entry in
            HardWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Your day and checklist. Tap a task to check it off.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular])
    }
}

@main
struct HardWidgets: WidgetBundle {
    var body: some Widget {
        HardWidget()
    }
}
