import SwiftUI
import UserNotifications
import WidgetKit
import AuthenticationServices

@main
struct SeventyFiveApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(model.colorScheme)
                .tint(model.accent.color)
                .onOpenURL { model.open($0) }
                .onChange(of: phase) { _, p in
                    if p == .active { model.foreground() }
                }
        }
    }
}

/// One person's challenge as the screens draw it: you (live, editable) or your friend (read only).
struct Snapshot {
    let isMe: Bool
    let code: String
    let name: String
    let attemptID: String
    let startKey: String
    let days: [Int: DayRecord]
    let avatar: UIImage?

    func day(_ n: Int) -> DayRecord { days[n] ?? DayRecord() }
    func date(_ n: Int) -> Date { DayMath.date(day: n, startKey: startKey) }
    func today(dayEnd: Int, now: Date = .now) -> Int { DayMath.number(startKey: startKey, now: now, dayEnd: dayEnd) }
    func currentDay(dayEnd: Int, now: Date = .now) -> Int { min(max(today(dayEnd: dayEnd, now: now), 1), Hard.days) }
    var completed: Int { days.values.filter(\.complete).count }
    var photoOwner: String { isMe ? "me" : code }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var s = HardStore.load()
    @Published var friend: RemoteProfile?
    @Published var friendDays: [Int: DayRecord] = [:]
    @Published var viewingFriend = false
    @Published var toast: String?
    @Published var celebrateDay: Int?
    @Published var syncProblem: String?
    @Published var now = Date.now
    @Published var avatar: UIImage? = UIImage(contentsOfFile: HardStore.avatarURL.path)

    private var pushTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var ticker: Task<Void, Never>?

    init() {
        ticker = Task { [weak self] in
            // Keeps the day number right across midnight and refreshes your friend while the app is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                self.now = .now
                if self.viewingFriend { await self.loadFriend() }
            }
        }
    }

    var accent: Accent { Accent.from(s) }
    var colorScheme: ColorScheme? {
        let options: [ColorScheme?] = [nil, .dark, .light]
        return options[min(max(s.settings.appearance, 0), 2)]
    }
    var dayEnd: Int { s.settings.dayEnd }
    var currentDay: Int { s.currentDay(now) }
    var todayNumber: Int { DayMath.number(startKey: s.startKey, now: now, dayEnd: dayEnd) }

    var me: Snapshot {
        Snapshot(isMe: true, code: s.myCode, name: s.firstName.isEmpty ? "You" : s.firstName, attemptID: s.attemptID, startKey: s.startKey, days: s.intDays, avatar: avatar)
    }
    var them: Snapshot? {
        guard let f = friend else { return nil }
        return Snapshot(isMe: false, code: f.code, name: f.name, attemptID: f.attemptID, startKey: f.startKey, days: friendDays, avatar: f.avatar)
    }
    var shown: Snapshot { viewingFriend ? (them ?? me) : me }

    // MARK: Changes

    func update(_ f: (inout HardState) -> Void) {
        s = HardActions.apply(f)
        schedulePush()
    }

    func binding<T>(_ kp: WritableKeyPath<HardState, T>, profile: Bool = false) -> Binding<T> {
        Binding(get: { self.s[keyPath: kp] }, set: { v in self.update { $0[keyPath: kp] = v; if profile { $0.profileDirty = true } } })
    }

    func toggle(_ task: HardTask, day: Int) {
        let wasComplete = s.day(day).complete
        update { $0.toggle(task.id, day: day) }
        let r = s.day(day)
        guard r.done.contains(task.id) else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        if r.complete && !wasComplete {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            celebrateDay = day
        } else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            show("\(task.short) done. \(Phrases.done.randomElement()!)")
        }
    }

    func addWater(_ oz: Int, day: Int) {
        let wasComplete = s.day(day).complete
        var reached = false
        update { reached = $0.addWater(oz, day: day) }
        UIImpactFeedbackGenerator(style: oz > 0 ? .medium : .light).impactOccurred()
        guard reached else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if s.day(day).complete && !wasComplete { celebrateDay = day } else { show("Gallon done 💧 Water checked off.") }
    }

    func addFood(_ e: FoodEntry, day: Int) {
        update { $0.editDay(day) { $0.food.append(e) } }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        show("\(e.name) added, \(e.kcal) cal")
    }

    func removeFood(_ id: UUID, day: Int) {
        update { $0.editDay(day) { $0.food.removeAll { $0.id == id } } }
    }

    func saveMeal(_ e: FoodEntry) {
        update { s in
            if let i = s.meals.firstIndex(where: { $0.id == e.id }) { s.meals[i] = e } else { s.meals.insert(e, at: 0) }
        }
        show("\(e.name) saved")
    }

    func deleteMeal(_ id: UUID) {
        update { $0.meals.removeAll { $0.id == id } }
    }

    func toggleFavorite(_ e: FoodEntry) {
        update { s in
            if let i = s.favorites.firstIndex(where: { $0.name.lowercased() == e.name.lowercased() }) {
                s.favorites.remove(at: i)
            } else {
                s.favorites.insert(e, at: 0)
            }
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func setNote(_ text: String, day: Int) {
        guard s.day(day).note != text else { return }
        update { $0.editDay(day) { $0.note = text } }
    }

    func setPhoto(_ image: UIImage?, day: Int) {
        let url = HardStore.photoURL(owner: "me", attempt: s.attemptID, day: day)
        if let image, let data = image.resized(1600).jpegData(compressionQuality: 0.78) {
            try? data.write(to: url, options: .atomic)
            update { $0.editDay(day) { $0.hasPhoto = true } }
            show("Progress picture saved")
        } else {
            try? FileManager.default.removeItem(at: url)
            update { $0.editDay(day) { $0.hasPhoto = false } }
        }
    }

    func setAvatar(_ image: UIImage) {
        guard let data = image.resized(600).jpegData(compressionQuality: 0.8) else { return }
        try? data.write(to: HardStore.avatarURL, options: .atomic)
        avatar = UIImage(data: data)
        update { $0.profileDirty = true }
    }

    func show(_ text: String) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { toast = text }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { toast = nil }
        }
    }

    // MARK: Account

    func signedIn(given: String?, family: String?) async {
        update {
            $0.signedIn = true
            if let given, !given.isEmpty { $0.firstName = given }
            if let family, !family.isEmpty { $0.lastName = family }
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        do {
            let code = try await Sync.myCode()
            update { $0.myCode = code }
            if let p = try await Sync.fetchProfile(code), !p.startKey.isEmpty { await restore(p) }
        } catch {
            syncProblem = Sync.describe(error)
        }
    }

    /// A reinstall or a new phone picks up where the cloud left off.
    private func restore(_ p: RemoteProfile) async {
        if let a = p.avatar, let data = a.jpegData(compressionQuality: 0.85) {
            try? data.write(to: HardStore.avatarURL, options: .atomic)
            avatar = a
        }
        let n = DayMath.number(startKey: p.startKey, dayEnd: dayEnd)
        let days = (try? await Sync.fetchDays(p.code, attempt: p.attemptID, upTo: n)) ?? [:]
        s = HardActions.apply {
            if $0.firstName.isEmpty { $0.firstName = p.name }
            $0.attemptID = p.attemptID
            $0.startKey = p.startKey
            $0.friendCode = p.friend
            $0.days = Dictionary(uniqueKeysWithValues: days.map { (String($0.key), $0.value) })
            $0.dirtyDays = []
            $0.profileDirty = false
        }
        await loadFriend()
    }

    func begin(start: Date) {
        update {
            $0.startKey = DayMath.key(start)
            $0.attemptID = UUID().uuidString
            $0.days = [:]
            $0.dirtyDays = []
            $0.profileDirty = true
        }
    }

    func restart() {
        update {
            $0.attemptID = UUID().uuidString
            $0.startKey = DayMath.key(DayMath.logicalToday(dayEnd: $0.settings.dayEnd))
            $0.days = [:]
            $0.dirtyDays = []
            $0.dismissedMiss = ""
            $0.profileDirty = true
        }
        viewingFriend = false
        show("Day one. Again. Let's go.")
    }

    func signOut() {
        HardStore.save(HardState())
        try? FileManager.default.removeItem(at: HardStore.avatarURL)
        s = HardStore.load()
        avatar = nil
        friend = nil
        friendDays = [:]
        viewingFriend = false
        Reminders.reschedule(s)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Friend

    var inviteURL: URL {
        var c = URLComponents(string: Hard.inviteBase)!
        c.queryItems = [URLQueryItem(name: "c", value: s.myCode), URLQueryItem(name: "n", value: s.firstName)]
        return c.url!
    }

    func open(_ url: URL) {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let code = items.first(where: { $0.name == "c" })?.value, !code.isEmpty else { return }
        addFriend(code)
    }

    func addFriend(_ raw: String) {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, code != s.myCode else { return }
        update { $0.friendCode = code; $0.profileDirty = true }
        Task {
            await loadFriend()
            if let f = friend { show("\(f.name) added"); viewingFriend = false }
            else { show("Could not find that friend yet") }
        }
    }

    func removeFriend() {
        update { $0.friendCode = ""; $0.profileDirty = true }
        friend = nil
        friendDays = [:]
        viewingFriend = false
    }

    func loadFriend() async {
        guard !s.friendCode.isEmpty else { friend = nil; return }
        guard let p = try? await Sync.fetchProfile(s.friendCode) else { return }
        let n = DayMath.number(startKey: p.startKey, dayEnd: dayEnd)
        let days = (try? await Sync.fetchDays(p.code, attempt: p.attemptID, upTo: n)) ?? friendDays
        friend = p
        friendDays = days
    }

    // MARK: Sync

    func foreground() {
        now = .now
        s = HardStore.load()
        Reminders.reschedule(s)
        Task { await refresh() }
    }

    func refresh() async {
        await push()
        if s.friendCode.isEmpty, !s.myCode.isEmpty, let code = try? await Sync.findFollower(of: s.myCode) {
            update { $0.friendCode = code; $0.profileDirty = true }
        }
        await loadFriend()
    }

    private func schedulePush() {
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await push()
        }
    }

    private func push() async {
        guard s.signedIn else { return }
        do {
            try await Sync.push()
            syncProblem = nil
        } catch {
            syncProblem = Sync.describe(error)
        }
        s = HardStore.load()
    }
}

extension UIImage {
    func resized(_ maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}

// MARK: - Root and onboarding

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if model.s.signedIn && !model.s.startKey.isEmpty {
                HomeView().transition(.opacity)
            } else {
                OnboardingView().transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.4), value: model.s.startKey.isEmpty)
    }
}

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @State private var name = ""
    @State private var start = Date.now
    @State private var working = false
    @State private var appear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LogoMark(size: 34, accent: model.accent)
                .padding(.top, 24)
            if !model.s.signedIn {
                Color.clear
                    .overlay {
                        Image("Welcome")
                            .resizable()
                            .scaledToFill()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.line))
                    .padding(.vertical, 24)
                    .accessibilityHidden(true)
            } else {
                Spacer()
            }
            if !model.s.signedIn {
                welcome
            } else {
                setup
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 16)
        .onAppear {
            name = model.s.firstName
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { appear = true }
        }
        .onChange(of: model.s.firstName) { _, n in if name.isEmpty { name = n } }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("SEVENTY\nFIVE DAYS.")
                .font(.system(size: 64, weight: .black))
                .italic()
                .fontWidth(.condensed)
                .foregroundStyle(Theme.text)
            Text("Seven tasks. Every day. No days off.")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 24)
            SignInWithAppleButton(.continue) { req in
                req.requestedScopes = [.fullName]
            } onCompletion: { result in
                guard case .success(let auth) = result, let cred = auth.credential as? ASAuthorizationAppleIDCredential else { return }
                working = true
                Task {
                    await model.signedIn(given: cred.fullName?.givenName, family: cred.fullName?.familyName)
                    working = false
                }
            }
            .signInWithAppleButtonStyle(model.colorScheme == .light ? .black : .white)
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(working ? 0.5 : 1)
            .disabled(working)
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("LET'S SET\nYOU UP.")
                .font(.system(size: 56, weight: .black))
                .italic()
                .fontWidth(.condensed)
                .foregroundStyle(Theme.text)
            VStack(alignment: .leading, spacing: 8) {
                Text("First name").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                TextField("Your name", text: $name)
                    .font(.system(size: 20, weight: .semibold))
                    .textContentType(.givenName)
                    .padding(16)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Day one").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                DatePicker("Day one", selection: $start, displayedComponents: .date)
                    .labelsHidden()
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text("Start today, pick a day coming up, or the day you already began.").font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            Button {
                model.update { $0.firstName = name.trimmingCharacters(in: .whitespaces); $0.profileDirty = true }
                model.begin(start: start)
            } label: {
                Text("Start")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(model.accent.ink)
                    .background(model.accent.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressStyle())
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
        }
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
