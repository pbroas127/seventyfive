import SwiftUI

/// Share images are always drawn dark so they look the same wherever they are posted.
struct ShareSheet: View {
    enum Kind {
        case day(Snapshot, Int)
        case calendar(Snapshot)
    }

    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let kind: Kind
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Group {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
                            .transition(.scale(scale: 0.94).combined(with: .opacity))
                    } else {
                        ProgressView().frame(maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)

                if let image {
                    HStack(spacing: 10) {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview(title, image: Image(uiImage: image))) {
                            action("Share", "square.and.arrow.up", primary: true)
                        }
                        Button {
                            UIPasteboard.general.image = image
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            model.show("Copied. Paste it anywhere.")
                        } label: { action("Copy", "doc.on.doc") }
                        Button {
                            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                            model.show("Saved to Photos")
                        } label: { action("Save", "square.and.arrow.down") }
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(20)
            .background(Theme.bg.ignoresSafeArea())
            .overlay(alignment: .top) { ToastView() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) }
            }
        }
        .task { render() }
    }

    private var title: String {
        switch kind {
        case .day(_, let n): "Day \(n)"
        case .calendar: "75 Days"
        }
    }

    private func action(_ label: String, _ icon: String, primary: Bool = false) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 18, weight: .bold))
            Text(label).font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(primary ? model.accent.ink : Theme.text)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(primary ? model.accent.color : Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func render() {
        let card: AnyView
        switch kind {
        case .day(let p, let n): card = AnyView(DayCard(person: p, day: n, accent: model.accent))
        case .calendar(let p): card = AnyView(CalendarCard(person: p, today: p.today(dayEnd: model.dayEnd), accent: model.accent))
        }
        let r = ImageRenderer(content: card.frame(width: 360, height: 640).environment(\.colorScheme, .dark))
        r.scale = 3
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { image = r.uiImage }
    }
}

private let cardBG = Color(hex: 0x0A0A0B)
private let cardText = Color(hex: 0xF5F5F7)
private let cardMuted = Color(hex: 0x8C8C94)
private let cardSurface = Color(hex: 0x17171A)

private struct CardHeader: View {
    let person: Snapshot
    let accent: Accent
    var body: some View {
        HStack {
            LogoMark(size: 26, accent: accent).foregroundStyle(cardText)
            Spacer()
            Text(person.name.uppercased())
                .font(.system(size: 13, weight: .heavy)).tracking(1.5)
                .foregroundStyle(cardMuted)
        }
    }
}

struct DayCard: View {
    let person: Snapshot
    let day: Int
    let accent: Accent

    var body: some View {
        let r = person.day(day)
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(person: person, accent: accent)
            Text("DAY \(day)")
                .font(.system(size: 88, weight: .black)).italic().fontWidth(.condensed)
                .foregroundStyle(cardText)
                .padding(.top, 34)
            Text(person.date(day).formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(cardMuted)
            VStack(alignment: .leading, spacing: 13) {
                ForEach(HardTask.all) { t in
                    let done = r.done.contains(t.id)
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().strokeBorder(cardMuted.opacity(0.5), lineWidth: 1.5)
                            if done {
                                Circle().fill(accent.color)
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .black)).foregroundStyle(accent.ink)
                            }
                        }
                        .frame(width: 22, height: 22)
                        Text(t.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(done ? cardText : cardMuted)
                    }
                }
            }
            .padding(.top, 30)
            Spacer()
            Group {
                if r.complete {
                    Label("ALL COMPLETE", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(accent.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(accent.color, in: Capsule())
                } else {
                    Text("\(r.count) OF \(HardTask.all.count) DONE").foregroundStyle(cardText)
                }
            }
            .font(.system(size: 15, weight: .heavy))
            .tracking(1.2)
        }
        .padding(28)
        .frame(width: 360, height: 640, alignment: .topLeading)
        .background(cardBG)
    }
}

struct CalendarCard: View {
    let person: Snapshot
    let today: Int
    let accent: Accent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(person: person, accent: accent)
            Text("\(person.completed)")
                .font(.system(size: 140, weight: .black)).italic().fontWidth(.condensed)
                .foregroundStyle(accent.color)
                .padding(.top, 40)
            Text("DAYS COMPLETE")
                .font(.system(size: 22, weight: .black)).italic().fontWidth(.condensed).tracking(1)
                .foregroundStyle(cardText)
            Text("Day \(min(max(today, 1), Hard.days)) of \(Hard.days)")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(cardMuted)
                .padding(.top, 4)
            Spacer()
            // Plain stacks, since ImageRenderer skips lazy grids.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<5, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(1...15, id: \.self) { col in
                            let n = row * 15 + col
                            let r = person.day(n)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(r.complete ? accent.color : (n <= today ? cardSurface : cardSurface.opacity(0.4)))
                                .overlay {
                                    if n == today && !r.complete {
                                        RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(accent.color, lineWidth: 1.5)
                                    }
                                }
                                .frame(width: 16, height: 16)
                        }
                    }
                }
            }
            .padding(.bottom, 12)
        }
        .padding(28)
        .frame(width: 360, height: 640, alignment: .topLeading)
        .background(cardBG)
    }
}
