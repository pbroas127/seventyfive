import SwiftUI
import VisionKit

// MARK: - Task list with water and food pills

struct TaskDetail {
    let text: String
    let progress: Double
    let action: () -> Void
}

/// The seven rows plus the progress picture, used on Home and in the calendar day view.
struct TaskList: View {
    @EnvironmentObject var model: AppModel
    let person: Snapshot
    let day: Int
    @State private var sheet: Which?

    enum Which: Identifiable {
        case food, water
        var id: Self { self }
    }

    var body: some View {
        let record = person.day(day)
        VStack(spacing: 10) {
            ForEach(HardTask.all) { task in
                TaskRow(task: task, done: record.done.contains(task.id), editable: person.isMe, detail: detail(task, record)) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { model.toggle(task, day: day) }
                }
            }
            PhotoRow(person: person, day: day)
        }
        .sheet(item: $sheet) { w in
            Group {
                switch w {
                case .food: FoodLogView(isMe: person.isMe, day: day)
                case .water: WaterSheet(day: day).presentationDetents([.height(460)])
                }
            }
            .environmentObject(model)
        }
    }

    private func detail(_ task: HardTask, _ r: DayRecord) -> TaskDetail? {
        guard person.isMe || r.foodShared else { return nil }
        let goals = person.isMe ? [model.s.settings.calorieGoal, model.s.settings.proteinGoal, model.s.settings.waterGoal] : (r.goals ?? [2000, 150, 128])
        switch task.id {
        case "water":
            return TaskDetail(text: "\(r.waterOz) oz", progress: Double(r.waterOz) / Double(max(goals[2], 1))) {
                if person.isMe { sheet = .water }
            }
        case "diet":
            if !person.isMe && r.food.isEmpty { return nil }
            return TaskDetail(text: r.food.isEmpty ? "Log food" : "\(r.kcal.formatted()) cal", progress: Double(r.kcal) / Double(max(goals[0], 1))) {
                sheet = .food
            }
        default:
            return nil
        }
    }
}

struct DetailPill: View {
    @EnvironmentObject var model: AppModel
    let detail: TaskDetail

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle().stroke(Theme.muted.opacity(0.25), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: min(detail.progress, 1))
                    .stroke(detail.progress > 1.02 ? Color(hex: 0xE5484D) : model.accent.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: detail.progress)
            Text(detail.text)
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Theme.raised, in: Capsule())
    }
}

// MARK: - Water

struct WaterSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let day: Int

    var body: some View {
        let oz = model.s.day(day).waterOz
        let goal = max(model.s.settings.waterGoal, 1)
        let fill = min(Double(oz) / Double(goal), 1)

        VStack(spacing: 22) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(oz)")
                    .font(.system(size: 64, weight: .black)).italic().fontWidth(.condensed)
                    .contentTransition(.numericText())
                Text("of \(goal) oz")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.top, 28)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.surface)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x3E8BFF), Color(hex: 0x62B0FF)], startPoint: .bottom, endPoint: .top))
                    .frame(height: 150 * fill)
                Image(systemName: "drop.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(fill > 0.55 ? .white : Theme.muted)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 110, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.line))
            .animation(.spring(response: 0.6, dampingFraction: 0.75), value: fill)

            HStack(spacing: 10) {
                ForEach([8, 16, 32], id: \.self) { amount in
                    Button { model.addWater(amount, day: day) } label: {
                        Text("+\(amount) oz")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(model.accent.ink)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(model.accent.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                Button { model.addWater(-8, day: day) } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 52, height: 52)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .accessibilityLabel("Remove 8 ounces")
            }
            .buttonStyle(PressStyle())
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .background(Theme.bg.ignoresSafeArea())
        .overlay(alignment: .top) { ToastView() }
    }
}

// MARK: - Food log

struct FoodLogView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let isMe: Bool
    let day: Int
    @State private var adding: Meal?

    var body: some View {
        let person = isMe ? model.me : (model.them ?? model.me)
        let r = person.day(day)
        let goals = isMe ? [model.s.settings.calorieGoal, model.s.settings.proteinGoal] : Array((r.goals ?? [2000, 150]).prefix(2))
        let left = goals[0] - r.kcal

        NavigationStack {
            List {
                Group {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .center, spacing: 18) {
                            ZStack {
                                Circle().stroke(Theme.raised, lineWidth: 10)
                                Circle()
                                    .trim(from: 0, to: min(Double(r.kcal) / Double(max(goals[0], 1)), 1))
                                    .stroke(left < 0 ? Color(hex: 0xE5484D) : model.accent.color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                VStack(spacing: 0) {
                                    Text("\(abs(left).formatted())")
                                        .font(.system(size: 26, weight: .black)).fontWidth(.condensed)
                                        .contentTransition(.numericText())
                                    Text(left < 0 ? "over" : "left")
                                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                                }
                            }
                            .frame(width: 104, height: 104)
                            VStack(alignment: .leading, spacing: 10) {
                                stat("Eaten", "\(r.kcal.formatted()) cal")
                                stat("Goal", "\(goals[0].formatted()) cal")
                                VStack(alignment: .leading, spacing: 6) {
                                    stat("Protein", "\(r.protein) of \(goals[1]) g")
                                    GeometryReader { g in
                                        Capsule().fill(model.accent.color)
                                            .frame(width: g.size.width * min(Double(r.protein) / Double(max(goals[1], 1)), 1), height: 6)
                                    }
                                    .frame(height: 6)
                                }
                            }
                        }
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: r.kcal)
                    }
                    .padding(.vertical, 8)
                }

                ForEach(Meal.allCases) { meal in
                    let items = r.food.filter { $0.meal == meal.rawValue }
                    Section {
                        ForEach(items) { e in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.name).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                                    Text([e.amount, "\(Int(e.protein.rounded())) g protein"].filter { !$0.isEmpty }.joined(separator: ", "))
                                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                                    if let parts = e.parts, !parts.isEmpty {
                                        Text(parts.map(\.name).joined(separator: ", "))
                                            .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2)
                                    }
                                }
                                Spacer()
                                Text("\(e.kcal)").font(.system(size: 16, weight: .bold)).monospacedDigit()
                            }
                            .swipeActions(edge: .trailing) {
                                if isMe {
                                    Button(role: .destructive) { model.removeFood(e.id, day: day) } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                            .swipeActions(edge: .leading) {
                                if isMe {
                                    Button { model.toggleFavorite(e) } label: { Label("Favorite", systemImage: "star.fill") }.tint(.yellow)
                                }
                            }
                        }
                        if isMe {
                            Button { adding = meal } label: {
                                Label("Add food", systemImage: "plus.circle.fill").font(.system(size: 15, weight: .semibold))
                            }
                        } else if items.isEmpty {
                            Text("Nothing logged").foregroundStyle(Theme.muted)
                        }
                    } header: {
                        HStack {
                            Label(meal.name, systemImage: meal.icon)
                            Spacer()
                            if !items.isEmpty { Text("\(items.reduce(0) { $0 + $1.kcal }) cal") }
                        }
                    }
                }
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(isMe ? "Food, day \(day)" : "\(person.name), day \(day)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) }
            }
            .overlay(alignment: .top) { ToastView() }
            .sheet(item: $adding) { meal in
                AddFoodSheet(day: day, meal: meal).environmentObject(model)
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).font(.system(size: 14, weight: .bold)).monospacedDigit()
        }
    }
}

// MARK: - Adding food

struct AddFoodSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let day: Int
    @State var meal: Meal
    /// Set when picking items for a meal you are building, instead of logging them.
    var collect: ((FoodEntry) -> Void)? = nil
    @State private var tab = 0
    @State private var path: [FoodResult] = []

    private func add(_ e: FoodEntry, close: Bool) {
        if let collect {
            collect(e)
            model.show("\(e.name) added to meal")
        } else {
            model.addFood(e, day: day)
        }
        if close { dismiss() }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Picker("Add by", selection: $tab) {
                    Text("Search").tag(0)
                    Text("Scan").tag(1)
                    Text("Saved").tag(2)
                    Text("Quick").tag(3)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                switch tab {
                case 0: SearchFoodView { path.append($0) }
                case 1: ScanFoodView { path.append($0) }
                case 2: RecentFoodView(day: day, meal: meal, canBuild: collect == nil) { add($0, close: false) }
                default: QuickAddView(meal: meal, buttonTitle: collect == nil ? "Add to \(meal.name)" : "Add to meal") { add($0, close: true) }
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(collect == nil ? "Add to \(meal.name)" : "Add to meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if collect == nil {
                    Menu {
                        Picker("Meal", selection: $meal) {
                            ForEach(Meal.allCases) { Label($0.name, systemImage: $0.icon).tag($0) }
                        }
                    } label: { Image(systemName: meal.icon) }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) }
            }
            .navigationDestination(for: FoodResult.self) { r in
                FoodAmountView(result: r, buttonTitle: collect == nil ? "Add to \(meal.name)" : "Add to meal", meal: meal) { add($0, close: true) }
            }
            .overlay(alignment: .top) { ToastView() }
        }
    }
}

struct SearchFoodView: View {
    var onPick: (FoodResult) -> Void
    @State private var query = ""
    @State private var results: [FoodResult] = []
    @State private var state = Phase.idle
    @FocusState private var focused: Bool

    enum Phase { case idle, loading, done, failed }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Search foods, like chicken breast", text: $query)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await run() } }
                if !query.isEmpty {
                    Button { query = ""; results = []; state = .idle } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                }
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)

            switch state {
            case .idle:
                hint("Type a food and tap search. Plain foods show first, then brands.")
            case .loading:
                ProgressView().frame(maxHeight: .infinity)
            case .failed:
                hint("Search did not load. Check your connection and try again.")
            case .done where results.isEmpty:
                hint("No matches. Try fewer words, or use Quick add.")
            case .done:
                List(results) { r in
                    Button { onPick(r) } label: { ResultRow(result: r) }
                        .listRowBackground(Theme.surface)
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .onAppear { focused = true }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Theme.muted)
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(maxHeight: .infinity, alignment: .top)
    }

    private func run() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        state = .loading
        do {
            results = try await FoodSearch.search(q)
            state = .done
        } catch {
            state = .failed
        }
    }
}

struct ResultRow: View {
    let result: FoodResult

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(2)
                Text(result.brand.isEmpty ? "Per 100 g" : result.brand.capitalized)
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(result.kcal100.rounded())) cal").font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(Theme.text)
                Text("\(Int(result.protein100.rounded())) g protein").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
    }
}

/// Pick how much you ate and see the numbers update before adding.
struct FoodAmountView: View {
    @EnvironmentObject var model: AppModel
    let result: FoodResult
    let buttonTitle: String
    let meal: Meal
    var onAdd: (FoodEntry) -> Void
    @State private var bySingle = true
    @State private var servings = 1.0
    @State private var grams = 100.0

    var body: some View {
        let hasServing = result.servingGrams != nil
        let g = hasServing && bySingle ? servings * (result.servingGrams ?? 100) : grams
        let kcal = Int((result.kcal100 * g / 100).rounded())
        let protein = result.protein100 * g / 100

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.name).font(.system(size: 26, weight: .black)).fontWidth(.condensed)
                    if !result.brand.isEmpty { Text(result.brand.capitalized).foregroundStyle(Theme.muted) }
                }
                HStack(spacing: 12) {
                    big("\(kcal)", "calories")
                    big("\(Int(protein.rounded()))", "g protein")
                }
                if hasServing {
                    Picker("Amount by", selection: $bySingle) {
                        Text("Servings").tag(true)
                        Text("Grams").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                if hasServing && bySingle {
                    amountRow(value: $servings, step: 0.5, unit: servings == 1 ? "serving" : "servings", note: result.servingText ?? "\(Int(result.servingGrams ?? 0)) g each")
                } else {
                    amountRow(value: $grams, step: 25, unit: "grams", note: "Nutrition is per 100 g")
                    HStack(spacing: 8) {
                        ForEach([50.0, 100, 150, 200, 300], id: \.self) { v in
                            Button("\(Int(v))") { grams = v }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(grams == v ? model.accent.ink : Theme.text)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(grams == v ? model.accent.color : Theme.surface, in: Capsule())
                        }
                    }
                }
                Button {
                    let amount = hasServing && bySingle ? "\(servings.formatted()) \(servings == 1 ? "serving" : "servings")" : "\(Int(grams)) g"
                    onAdd(FoodEntry(name: result.name, kcal: kcal, protein: protein, meal: meal.rawValue, amount: amount))
                } label: {
                    Text(buttonTitle)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(model.accent.ink)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(model.accent.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressStyle())
            }
            .padding(20)
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { bySingle = hasServing }
        .animation(.smooth(duration: 0.25), value: bySingle)
    }

    private func big(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 40, weight: .black)).italic().fontWidth(.condensed).contentTransition(.numericText())
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func amountRow(value: Binding<Double>, step: Double, unit: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button { value.wrappedValue = max(step, value.wrappedValue - step) } label: { Image(systemName: "minus") }
                    .frame(width: 48, height: 48).background(Theme.surface, in: Circle())
                TextField("Amount", value: value, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 28, weight: .black)).fontWidth(.condensed)
                Button { value.wrappedValue += step } label: { Image(systemName: "plus") }
                    .frame(width: 48, height: 48).background(Theme.surface, in: Circle())
            }
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Theme.text)
            Text("\(unit), \(note)").font(.system(size: 13)).foregroundStyle(Theme.muted)
        }
    }
}

struct ScanFoodView: View {
    var onFound: (FoodResult) -> Void
    @State private var looking = false
    @State private var missed: String?
    @State private var lastCode = ""

    var body: some View {
        VStack(spacing: 14) {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                BarcodeScanner { code in
                    guard !looking, code != lastCode else { return }
                    lastCode = code
                    looking = true
                    missed = nil
                    Task {
                        if let r = await FoodSearch.barcode(code) {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            onFound(r)
                        } else {
                            missed = "No match for that barcode. Try Search or Quick add."
                        }
                        looking = false
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    if looking { ProgressView().controlSize(.large).padding(20).background(.ultraThinMaterial, in: Circle()) }
                }
                Text(missed ?? "Point the camera at a barcode.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            } else {
                Text("Barcode scanning needs camera access. Turn it on in Settings, or use Search.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(32)
                Spacer()
            }
        }
        .padding(16)
    }
}

struct BarcodeScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode()], qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        DispatchQueue.main.async { try? vc.startScanning() }
        return vc
    }
    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) { vc.stopScanning() }
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let b) = item, let code = b.payloadStringValue { onCode(code); return }
            }
        }
    }
}

struct RecentFoodView: View {
    @EnvironmentObject var model: AppModel
    let day: Int
    let meal: Meal
    var canBuild = true
    var onAdd: (FoodEntry) -> Void
    @State private var building = false
    @State private var editing: FoodEntry?

    var body: some View {
        let favorites = model.s.favorites
        let recents = model.s.recentFoods.filter { r in !favorites.contains { $0.name.lowercased() == r.name.lowercased() } }
        List {
            Section {
                if canBuild {
                    Button { building = true } label: {
                        Label("Create a meal", systemImage: "square.stack.3d.up.fill")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .listRowBackground(Theme.surface)
                }
                ForEach(model.s.meals) { m in
                    row(m, favorite: nil)
                        .contextMenu {
                            if canBuild { Button { editing = m } label: { Label("Edit meal", systemImage: "pencil") } }
                            Button(role: .destructive) { model.deleteMeal(m.id) } label: { Label("Delete meal", systemImage: "trash") }
                        }
                        .swipeActions {
                            Button(role: .destructive) { model.deleteMeal(m.id) } label: { Label("Delete", systemImage: "trash") }
                            if canBuild { Button { editing = m } label: { Label("Edit", systemImage: "pencil") }.tint(Theme.muted) }
                        }
                }
            } header: {
                Text("My meals")
            } footer: {
                if model.s.meals.isEmpty && canBuild {
                    Text("Search or scan several foods and save them as one meal, like your usual breakfast.")
                }
            }
            if !favorites.isEmpty {
                Section("Favorites") { ForEach(favorites) { row($0, favorite: true) } }
            }
            if !recents.isEmpty {
                Section("Recent") { ForEach(recents) { row($0, favorite: false) } }
            }
        }
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $building) {
            NavigationStack { MealBuilderView(day: day, meal: meal) }.environmentObject(model)
        }
        .sheet(item: $editing) { m in
            NavigationStack { MealBuilderView(day: day, meal: meal, existing: m) }.environmentObject(model)
        }
    }

    /// favorite is nil for saved meals, which have no star.
    private func row(_ e: FoodEntry, favorite: Bool?) -> some View {
        HStack(spacing: 12) {
            if let favorite {
                Button { model.toggleFavorite(e) } label: {
                    Image(systemName: favorite ? "star.fill" : "star")
                        .foregroundStyle(favorite ? Color.yellow : Theme.muted)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(model.accent.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text("\(e.kcal) cal, \(Int(e.protein.rounded())) g protein\(e.amount.isEmpty ? "" : ", \(e.amount)")")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            Button {
                onAdd(e.copy(meal: meal.rawValue))
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(model.accent.ink)
                    .frame(width: 32, height: 32)
                    .background(model.accent.color, in: Circle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Add \(e.name)")
        }
        .listRowBackground(Theme.surface)
    }
}

/// Build one meal out of several foods, then save it to reuse with a single tap.
struct MealBuilderView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let day: Int
    let meal: Meal
    var existing: FoodEntry? = nil
    @State private var name = ""
    @State private var items: [FoodEntry] = []
    @State private var adding = false
    @State private var loaded = false

    var body: some View {
        let kcal = items.reduce(0) { $0 + $1.kcal }
        let protein = items.reduce(0.0) { $0 + $1.protein }

        List {
            Section {
                TextField("Meal name, like Chicken rice bowl", text: $name)
                    .font(.system(size: 17, weight: .semibold))
            }
            .listRowBackground(Theme.surface)

            Section {
                HStack(spacing: 12) {
                    total("\(kcal)", "calories")
                    total("\(Int(protein.rounded()))", "g protein")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(items) { e in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.name).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                            Text([e.amount, "\(Int(e.protein.rounded())) g protein"].filter { !$0.isEmpty }.joined(separator: ", "))
                                .font(.system(size: 13)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Text("\(e.kcal)").font(.system(size: 15, weight: .bold)).monospacedDigit()
                    }
                }
                .onDelete { items.remove(atOffsets: $0) }
                Button { adding = true } label: {
                    Label(items.isEmpty ? "Add the first item" : "Add another item", systemImage: "plus.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                }
            } header: {
                Text(items.isEmpty ? "Items" : "Items (\(items.count))")
            } footer: {
                Text("Search, scan, or quick add each part. Swipe to remove one.")
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .animation(.smooth(duration: 0.3), value: items)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    let e = built()
                    model.saveMeal(e)
                    model.addFood(e.copy(meal: meal.rawValue), day: day)
                    dismiss()
                } label: {
                    Text("Save and add to \(meal.name)")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(model.accent.ink)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(model.accent.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Button {
                    model.saveMeal(built())
                    dismiss()
                } label: {
                    Text("Save meal")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .buttonStyle(PressStyle())
            .disabled(items.isEmpty)
            .opacity(items.isEmpty ? 0.4 : 1)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(Theme.bg)
        }
        .navigationTitle(existing == nil ? "New meal" : "Edit meal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
        }
        .overlay(alignment: .top) { ToastView() }
        .sheet(isPresented: $adding) {
            AddFoodSheet(day: day, meal: meal, collect: { items.append($0) }).environmentObject(model)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let existing {
                name = existing.name
                items = existing.parts ?? []
            }
        }
    }

    private func built() -> FoodEntry {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        var e = FoodEntry(
            name: trimmed.isEmpty ? "My meal" : trimmed,
            kcal: items.reduce(0) { $0 + $1.kcal },
            protein: items.reduce(0.0) { $0 + $1.protein },
            meal: meal.rawValue,
            amount: items.count == 1 ? "1 item" : "\(items.count) items"
        )
        e.parts = items
        if let existing { e.id = existing.id }
        return e
    }

    private func total(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 36, weight: .black)).italic().fontWidth(.condensed).contentTransition(.numericText())
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct QuickAddView: View {
    @EnvironmentObject var model: AppModel
    let meal: Meal
    let buttonTitle: String
    var onAdd: (FoodEntry) -> Void
    @State private var name = ""
    @State private var kcal: Int?
    @State private var protein: Int?
    @FocusState private var focus: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Name (optional)") {
                TextField("Protein shake", text: $name).focused($focus, equals: 0)
            }
            HStack(spacing: 12) {
                field("Calories") {
                    TextField("0", value: $kcal, format: .number).keyboardType(.numberPad).focused($focus, equals: 1)
                }
                field("Protein (g)") {
                    TextField("0", value: $protein, format: .number).keyboardType(.numberPad).focused($focus, equals: 2)
                }
            }
            Button {
                onAdd(FoodEntry(name: name.isEmpty ? "Quick add" : name, kcal: kcal ?? 0, protein: Double(protein ?? 0), meal: meal.rawValue))
            } label: {
                Text(buttonTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(model.accent.ink)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(model.accent.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressStyle())
            .disabled((kcal ?? 0) <= 0)
            .opacity((kcal ?? 0) <= 0 ? 0.4 : 1)
            Spacer()
        }
        .padding(16)
        .onAppear { focus = 1 }
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
            content()
                .font(.system(size: 18, weight: .semibold))
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
