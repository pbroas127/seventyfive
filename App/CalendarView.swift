import SwiftUI

struct CalendarSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var friendTab = false
    @State private var share = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        let person = (friendTab ? model.them : nil) ?? model.me
        let today = person.today(dayEnd: model.dayEnd, now: model.now)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let f = model.them {
                        Picker("Person", selection: $friendTab.animation(.smooth)) {
                            Text(model.me.name).tag(false)
                            Text(f.name).tag(true)
                        }
                        .pickerStyle(.segmented)
                    }

                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text("\(person.completed)")
                            .font(.system(size: 64, weight: .black)).italic().fontWidth(.condensed)
                            .contentTransition(.numericText())
                        Text("of \(Hard.days) days complete")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }

                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(1...Hard.days, id: \.self) { n in
                            if n <= today {
                                NavigationLink(value: n) { DayCell(n: n, record: person.day(n), today: today) }
                                    .buttonStyle(PressStyle())
                            } else {
                                DayCell(n: n, record: DayRecord(), today: today)
                            }
                        }
                    }
                    .id(person.isMe)
                    .transition(.opacity)
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("75 Days")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { share = true } label: { Image(systemName: "square.and.arrow.up") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .navigationDestination(for: Int.self) { n in
                DayDetail(isMe: person.isMe, day: n)
            }
            .sheet(isPresented: $share) { ShareSheet(kind: .calendar(person)).environmentObject(model) }
            .refreshable { await model.refresh() }
        }
        .onAppear { friendTab = model.viewingFriend && model.them != nil }
    }
}

struct DayCell: View {
    @EnvironmentObject var model: AppModel
    let n: Int
    let record: DayRecord
    let today: Int

    var body: some View {
        let past = n < today
        let isToday = n == today
        let future = n > today

        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(record.complete ? model.accent.color : Theme.surface)
            if isToday && !record.complete {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(model.accent.color, lineWidth: 2)
            }
            VStack(spacing: 2) {
                Text("\(n)")
                    .font(.system(size: 19, weight: .black)).fontWidth(.condensed)
                    .foregroundStyle(record.complete ? model.accent.ink : (future ? Theme.muted.opacity(0.5) : Theme.text))
                if record.complete {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .black)).foregroundStyle(model.accent.ink)
                } else if past {
                    Text("\(record.count)/\(HardTask.all.count)").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
                }
            }
            if record.hasPhoto {
                Image(systemName: "camera.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(record.complete ? model.accent.ink.opacity(0.7) : Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(7)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .opacity(future ? 0.55 : 1)
    }
}

struct DayDetail: View {
    @EnvironmentObject var model: AppModel
    let isMe: Bool
    let day: Int

    var body: some View {
        let person = isMe ? model.me : (model.them ?? model.me)
        let record = person.day(day)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(person.name.uppercased())
                    .font(.system(size: 13, weight: .heavy)).tracking(1.5)
                    .foregroundStyle(model.accent.color)
                Text("DAY \(day)")
                    .font(.system(size: 72, weight: .black)).italic().fontWidth(.condensed)
                Text(person.date(day).formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.muted)

                ProgressStrip(count: record.count)
                    .padding(.vertical, 20)

                TaskList(person: person, day: day)

                NoteCard(person: person, day: day)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.bg.ignoresSafeArea())
        .overlay(alignment: .top) { ToastView() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareDayButton(person: person, day: day)
            }
        }
    }
}

struct ShareDayButton: View {
    @EnvironmentObject var model: AppModel
    let person: Snapshot
    let day: Int
    @State private var open = false

    var body: some View {
        Button { open = true } label: { Image(systemName: "square.and.arrow.up") }
            .sheet(isPresented: $open) { ShareSheet(kind: .day(person, day)).environmentObject(model) }
    }
}
