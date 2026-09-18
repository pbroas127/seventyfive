import SwiftUI
import PhotosUI

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var sheet: Sheet?
    @State private var confirmRestart = false

    enum Sheet: Identifiable {
        case calendar, settings, addFriend, shareDay
        var id: Self { self }
    }

    var body: some View {
        let person = model.shown
        let day = person.currentDay(dayEnd: model.dayEnd, now: model.now)
        let record = person.day(day)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                PeopleSwitcher(onAdd: { sheet = .addFriend })
                    .padding(.top, 18)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        Text("DAY \(day)")
                            .font(.system(size: 92, weight: .black))
                            .italic()
                            .fontWidth(.condensed)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                        Text("of \(Hard.days)")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    Text(person.date(day).formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 20)
                .id(person.isMe)
                .transition(.opacity)

                if person.isMe { missedBanner.padding(.top, 18) }

                ProgressStrip(count: record.count)
                    .padding(.top, 22)
                    .padding(.bottom, 14)

                VStack(spacing: 10) {
                    ForEach(HardTask.all) { task in
                        TaskRow(task: task, done: record.done.contains(task.id), editable: person.isMe) {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { model.toggle(task, day: day) }
                        }
                    }
                    PhotoRow(person: person, day: day)
                }

                NoteCard(person: person, day: day)
                    .padding(.top, 22)

                Color.clear.frame(height: 110)
            }
            .padding(.horizontal, 20)
            .animation(.smooth(duration: 0.35), value: model.viewingFriend)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await model.refresh() }
        .overlay(alignment: .top) { ToastView() }
        .overlay(alignment: .bottomTrailing) {
            Button { sheet = .shareDay } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(model.accent.ink)
                    .frame(width: 60, height: 60)
                    .background(model.accent.color, in: Circle())
                    .shadow(color: model.accent.color.opacity(0.35), radius: 16, y: 8)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Share today")
            .padding(.trailing, 22)
            .padding(.bottom, 12)
        }
        .overlay {
            if let d = model.celebrateDay {
                CelebrationView(day: d, onShare: { model.celebrateDay = nil; sheet = .shareDay })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.celebrateDay)
        .sheet(item: $sheet) { s in
            switch s {
            case .calendar: CalendarSheet()
            case .settings: SettingsView()
            case .addFriend: AddFriendSheet().presentationDetents([.medium, .large])
            case .shareDay: ShareSheet(kind: .day(model.shown, model.shown.currentDay(dayEnd: model.dayEnd)))
            }
        }
        .environmentObject(model)
        .confirmationDialog("Start over from day one?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Start over", role: .destructive) { model.restart() }
        } message: {
            Text("Your current attempt stays in the cloud, but the app begins again at day one.")
        }
        .task { await model.refresh() }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            LogoMark(size: 30, accent: model.accent)
            Spacer()
            iconButton("calendar") { sheet = .calendar }
            iconButton("gearshape.fill") { sheet = .settings }
        }
        .padding(.top, 8)
    }

    private func iconButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.line))
        }
        .buttonStyle(PressStyle())
    }

    @ViewBuilder private var missedBanner: some View {
        let today = model.todayNumber
        let missed = today - 1
        let key = "\(model.s.attemptID).\(missed)"
        if missed >= 1, missed < Hard.days, !model.s.day(missed).complete, model.s.dismissedMiss != key {
            VStack(alignment: .leading, spacing: 12) {
                Text("Day \(missed) was not finished")
                    .font(.system(size: 17, weight: .bold))
                Text("75 Hard means starting over after a miss. If you just forgot to check something, fix it in the calendar.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                HStack(spacing: 10) {
                    Button("Start over") { confirmRestart = true }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(model.accent.ink)
                        .padding(.horizontal, 16).frame(height: 38)
                        .background(model.accent.color, in: Capsule())
                    Button("Dismiss") { model.update { $0.dismissedMiss = key } }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 16).frame(height: 38)
                        .background(Theme.raised, in: Capsule())
                }
                .buttonStyle(PressStyle())
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(model.accent.color.opacity(0.5)))
        }
    }
}

// MARK: - People

struct PeopleSwitcher: View {
    @EnvironmentObject var model: AppModel
    var onAdd: () -> Void
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 8) {
            pill(model.me, selected: !model.viewingFriend) { model.viewingFriend = false }
            if let f = model.them {
                pill(f, selected: model.viewingFriend) {
                    model.viewingFriend = true
                    Task { await model.loadFriend() }
                }
            } else {
                Button(action: onAdd) {
                    Label("Add friend", systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .overlay(Capsule().strokeBorder(Theme.muted.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                }
                .buttonStyle(PressStyle())
            }
            Spacer()
        }
    }

    private func pill(_ p: Snapshot, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { action() }
        } label: {
            HStack(spacing: 8) {
                Avatar(image: p.avatar, name: p.name, size: 28, selected: selected)
                Text(p.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? Theme.text : Theme.muted)
            }
            .padding(.leading, 6).padding(.trailing, 14)
            .frame(height: 40)
            .background {
                if selected {
                    Capsule().fill(Theme.surface)
                        .overlay(Capsule().strokeBorder(Theme.line))
                        .matchedGeometryEffect(id: "pill", in: ns)
                }
            }
        }
        .buttonStyle(PressStyle())
    }
}

struct Avatar: View {
    @EnvironmentObject var model: AppModel
    var image: UIImage?
    var name: String
    var size: CGFloat
    var selected = true

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.46, weight: .black))
                    .foregroundStyle(selected ? model.accent.ink : Theme.text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(selected ? model.accent.color : Theme.raised)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - Tasks

struct ProgressStrip: View {
    @EnvironmentObject var model: AppModel
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(0..<HardTask.all.count, id: \.self) { i in
                    Capsule()
                        .fill(i < count ? model.accent.color : Theme.raised)
                        .frame(height: 6)
                }
            }
            Text(count == HardTask.all.count ? "All complete" : "\(count) of \(HardTask.all.count)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(count == HardTask.all.count ? model.accent.color : Theme.muted)
                .contentTransition(.numericText())
                .fixedSize()
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: count)
    }
}

struct TaskRow: View {
    @EnvironmentObject var model: AppModel
    let task: HardTask
    let done: Bool
    let editable: Bool
    let action: () -> Void
    @State private var sweep: CGFloat = 0

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                CheckCircle(done: done)
                Image(systemName: task.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(done ? Theme.muted : model.accent.color)
                    .frame(width: 22)
                Text(task.title)
                    .font(.system(size: 17, weight: .semibold))
                    .strikethrough(done, color: Theme.muted)
                    .foregroundStyle(done ? Theme.muted : Theme.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                if done {
                    Text("COMPLETE")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.1)
                        .foregroundStyle(model.accent.color)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 64)
            .background {
                ZStack(alignment: .leading) {
                    Theme.surface
                    GeometryReader { g in
                        model.accent.color.opacity(0.14)
                            .frame(width: g.size.width * sweep)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line))
            .opacity(done ? 0.62 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .allowsHitTesting(editable)
        .onAppear { sweep = done ? 1 : 0 }
        .onChange(of: done) { _, d in
            withAnimation(.easeOut(duration: d ? 0.55 : 0.3)) { sweep = d ? 1 : 0 }
        }
        .accessibilityLabel(task.title)
        .accessibilityValue(done ? "Complete" : "Not done")
    }
}

struct CheckCircle: View {
    @EnvironmentObject var model: AppModel
    let done: Bool
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().strokeBorder(Theme.muted.opacity(0.45), lineWidth: 2)
            Circle().fill(model.accent.color)
                .scaleEffect(done ? 1 : 0.3)
                .opacity(done ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.43, weight: .black))
                .foregroundStyle(model.accent.ink)
                .scaleEffect(done ? 1 : 0.2)
                .opacity(done ? 1 : 0)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.35, dampingFraction: 0.55), value: done)
    }
}

// MARK: - Photo

struct PhotoRow: View {
    @EnvironmentObject var model: AppModel
    let person: Snapshot
    let day: Int
    @State private var ask = false
    @State private var camera = false
    @State private var library = false
    @State private var pick: PhotosPickerItem?
    @State private var viewer = false

    var body: some View {
        let has = person.day(day).hasPhoto
        if has || person.isMe {
            Button {
                if has { viewer = true } else { ask = true }
            } label: {
                HStack(spacing: 14) {
                    if has {
                        ProgressPhoto(person: person, day: day)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(model.accent.color)
                            .frame(width: 44, height: 44)
                            .background(model.accent.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Progress picture").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                        Text(has ? "Tap to view" : "Optional").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Image(systemName: has ? "chevron.right" : "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 68)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.muted.opacity(has ? 0.15 : 0.35), style: StrokeStyle(lineWidth: 1.5, dash: has ? [] : [6, 5])))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .confirmationDialog("Progress picture", isPresented: $ask) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take photo") { camera = true }
                }
                Button("Choose from library") { library = true }
            }
            .photosPicker(isPresented: $library, selection: $pick, matching: .images)
            .onChange(of: pick) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        model.setPhoto(img, day: day)
                    }
                    pick = nil
                }
            }
            .fullScreenCover(isPresented: $camera) {
                CameraPicker { img in model.setPhoto(img, day: day) }.ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $viewer) {
                PhotoViewer(person: person, day: day)
            }
        }
    }
}

/// Loads a progress picture from disk, or from the cloud the first time.
struct ProgressPhoto: View {
    @EnvironmentObject var model: AppModel
    let person: Snapshot
    let day: Int
    var fit = false
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.raised
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: fit ? .fit : .fill)
                    .transition(.opacity)
            } else {
                ProgressView()
            }
        }
        .task(id: "\(person.code)\(person.attemptID)\(day)\(person.day(day).hasPhoto)") {
            image = await ProgressPhoto.load(person, day)
        }
    }

    static func load(_ p: Snapshot, _ day: Int) async -> UIImage? {
        let url = HardStore.photoURL(owner: p.photoOwner, attempt: p.attemptID, day: day)
        if let img = UIImage(contentsOfFile: url.path) { return img }
        guard !p.code.isEmpty, let got = await Sync.photo(code: p.code, attempt: p.attemptID, day: day, to: url) else { return nil }
        return UIImage(contentsOfFile: got.path)
    }
}

struct PhotoViewer: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let person: Snapshot
    let day: Int
    @State private var confirmDelete = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            ProgressPhoto(person: person, day: day, fit: true)
                .ignoresSafeArea()
            HStack {
                Button { dismiss() } label: { circleIcon("xmark") }
                Spacer()
                Button {
                    Task {
                        if let img = await ProgressPhoto.load(person, day) {
                            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                            model.show("Saved to Photos")
                        }
                    }
                } label: { circleIcon("square.and.arrow.down") }
                if person.isMe {
                    Button { confirmDelete = true } label: { circleIcon("trash") }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .overlay(alignment: .top) { ToastView().padding(.top, 60) }
        .confirmationDialog("Remove this picture?", isPresented: $confirmDelete) {
            Button("Remove", role: .destructive) { model.setPhoto(nil, day: day); dismiss() }
        }
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: Circle())
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.cameraDevice = .front
        c.delegate = context.coordinator
        return c
    }
    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - Notes

struct NoteCard: View {
    @EnvironmentObject var model: AppModel
    let person: Snapshot
    let day: Int
    @State private var text = ""
    @State private var save: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.muted)
            if person.isMe {
                TextField("How did today go?", text: $text, axis: .vertical)
                    .font(.system(size: 16))
                    .lineLimit(3...12)
                    .focused($focused)
                    .onChange(of: text) { _, t in
                        save?.cancel()
                        save = Task {
                            try? await Task.sleep(for: .milliseconds(600))
                            guard !Task.isCancelled else { return }
                            model.setNote(t, day: day)
                        }
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { focused = false }.fontWeight(.semibold)
                        }
                    }
            } else {
                let note = person.day(day).note
                Text(note.isEmpty ? "No notes yet" : note)
                    .font(.system(size: 16))
                    .foregroundStyle(note.isEmpty ? Theme.muted : Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line))
        .onAppear { text = person.day(day).note }
        .onChange(of: "\(person.isMe)\(day)") { _, _ in text = person.day(day).note }
        .onDisappear { if person.isMe { model.setNote(text, day: day) } }
    }
}

// MARK: - Feedback

struct ToastView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let t = model.toast {
            Text(t)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.line))
                .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(t)
        }
    }
}

struct CelebrationView: View {
    @EnvironmentObject var model: AppModel
    let day: Int
    var onShare: () -> Void
    @State private var shown = false
    @State private var line = ""

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Theme.bg.opacity(0.55).ignoresSafeArea()
            Confetti(colors: [model.accent.color, Theme.text, model.accent.color.opacity(0.6)])
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(model.accent.color)
                    Image(systemName: "checkmark").font(.system(size: 54, weight: .black)).foregroundStyle(model.accent.ink)
                }
                .frame(width: 120, height: 120)
                .scaleEffect(shown ? 1 : 0.2)
                .rotationEffect(.degrees(shown ? 0 : -30))
                VStack(spacing: 2) {
                    Text("DAY \(day)")
                        .font(.system(size: 76, weight: .black)).italic().fontWidth(.condensed)
                    Text("COMPLETE")
                        .font(.system(size: 20, weight: .heavy)).tracking(6)
                        .foregroundStyle(model.accent.color)
                }
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 20)
                Text(line)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .opacity(shown ? 1 : 0)
                HStack(spacing: 12) {
                    Button { onShare() } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(model.accent.ink)
                            .frame(width: 140, height: 52)
                            .background(model.accent.color, in: Capsule())
                    }
                    Button { model.celebrateDay = nil } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 140, height: 52)
                            .background(Theme.raised, in: Capsule())
                    }
                }
                .buttonStyle(PressStyle())
                .padding(.top, 12)
                .opacity(shown ? 1 : 0)
            }
        }
        .onAppear {
            line = Phrases.fill(Phrases.complete.randomElement()!, d: day)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6).delay(0.05)) { shown = true }
        }
        .onTapGesture { model.celebrateDay = nil }
    }
}

/// A short burst of falling pieces drawn in one Canvas.
struct Confetti: View {
    var colors: [Color]
    @State private var start = Date.now
    @State private var pieces: [Piece] = (0..<90).map { _ in Piece() }

    struct Piece {
        let x = CGFloat.random(in: 0...1)
        let vx = CGFloat.random(in: -60...60)
        let vy = CGFloat.random(in: -520 ... -220)
        let spin = Double.random(in: -8...8)
        let size = CGSize(width: .random(in: 6...11), height: .random(in: 10...18))
        let color = Int.random(in: 0..<3)
        let delay = Double.random(in: 0...0.25)
    }

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSince(start)
                for p in pieces {
                    let tt = max(0, t - p.delay)
                    let x = p.x * size.width + p.vx * tt
                    let y = size.height * 0.35 + p.vy * tt + 0.5 * 900 * tt * tt
                    guard y < size.height + 40 else { continue }
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(p.spin * tt))
                    c.opacity = max(0, 1 - tt / 2.6)
                    c.fill(Path(roundedRect: CGRect(origin: CGPoint(x: -p.size.width / 2, y: -p.size.height / 2), size: p.size), cornerRadius: 2),
                           with: .color(colors[p.color % colors.count]))
                }
            }
        }
        .onAppear { start = .now }
    }
}

// MARK: - Add a friend

struct AddFriendSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add a friend")
                .font(.system(size: 34, weight: .black)).italic().fontWidth(.condensed)
                .padding(.top, 28)
            Text("Send your link. When they open it, you both show up in each other's app.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.muted)
            if model.s.myCode.isEmpty {
                Text(model.syncProblem ?? "Connecting to iCloud…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.muted)
            } else {
                ShareLink(item: model.inviteURL, message: Text("Join my 75 Hard. Tap to add me:")) {
                    Label("Send invite link", systemImage: "paperplane.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(model.accent.ink)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(model.accent.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressStyle())
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Got a code instead?").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                HStack {
                    TextField("Paste code", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 16, design: .monospaced))
                    Button("Add") { model.addFriend(code); dismiss() }
                        .fontWeight(.bold)
                        .disabled(code.isEmpty)
                }
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Theme.bg.ignoresSafeArea())
    }
}
