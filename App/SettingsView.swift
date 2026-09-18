import SwiftUI
import PhotosUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var avatarItem: PhotosPickerItem?
    @State private var confirmRestart = false
    @State private var confirmSignOut = false
    @State private var confirmRemove = false

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    profile
                    look
                    reminders
                    if model.s.settings.notifications { NudgeSection() }
                    food
                    challenge
                    friend
                    account
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) }
            }
            .overlay(alignment: .top) { ToastView() }
        }
        .onChange(of: avatarItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { model.setAvatar(img) }
                avatarItem = nil
            }
        }
        .confirmationDialog("Start over from day one?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Start over", role: .destructive) { model.restart(); dismiss() }
        }
        .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { model.signOut(); dismiss() }
        } message: {
            Text("Your days stay in iCloud and come back when you sign in again.")
        }
        .confirmationDialog("Remove friend?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { model.removeFriend() }
        }
    }

    private var profile: some View {
        Section {
            HStack(spacing: 16) {
                PhotosPicker(selection: $avatarItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        Avatar(image: model.avatar, name: model.s.firstName, size: 64)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(model.accent.ink)
                            .frame(width: 22, height: 22)
                            .background(model.accent.color, in: Circle())
                    }
                }
                .buttonStyle(.plain)
                VStack(spacing: 10) {
                    TextField("First name", text: model.binding(\.firstName, profile: true))
                        .font(.system(size: 17, weight: .semibold))
                        .textContentType(.givenName)
                    Divider()
                    TextField("Last name", text: model.binding(\.lastName))
                        .font(.system(size: 17))
                        .textContentType(.familyName)
                }
            }
            .padding(.vertical, 4)
        } footer: {
            Text("Only your first name is shown to your friend.")
        }
    }

    private var look: some View {
        Section("Look") {
            Picker("Appearance", selection: model.binding(\.settings.appearance)) {
                Text("System").tag(0)
                Text("Dark").tag(1)
                Text("Light").tag(2)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
            HStack(spacing: 0) {
                ForEach(Accent.allCases) { a in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.smooth) { model.update { $0.settings.accent = a.rawValue } }
                    } label: {
                        ZStack {
                            Circle().fill(a.color).frame(width: 34, height: 34)
                            if model.accent == a {
                                Circle().strokeBorder(Theme.text, lineWidth: 2.5).frame(width: 44, height: 44)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(a.name)
                }
            }
        }
    }

    private var reminders: some View {
        Section {
            Toggle("Reminders", isOn: model.binding(\.settings.notifications))
            if model.s.settings.notifications {
                ForEach(HardTask.all) { task in
                    ReminderRow(task: task)
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Turn on a reminder for any task you want. They skip anything already checked off.")
        }
        .animation(.smooth, value: model.s.settings.notifications)
    }

    private var food: some View {
        Section {
            numberRow("Calories", model.binding(\.settings.calorieGoal), unit: "cal")
            numberRow("Protein", model.binding(\.settings.proteinGoal), unit: "g")
            Stepper(value: model.binding(\.settings.waterGoal), in: 32...256, step: 8) {
                HStack {
                    Text("Water")
                    Spacer()
                    Text("\(model.s.settings.waterGoal) oz").foregroundStyle(Theme.muted).monospacedDigit()
                }
            }
            Toggle("Show my food to my friend", isOn: model.binding(\.settings.shareFood))
        } header: {
            Text("Daily goals")
        } footer: {
            Text("Hitting your water goal checks off the gallon for you. Your diet stays your call to check.")
        }
    }

    private func numberRow(_ label: String, _ value: Binding<Int>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).foregroundStyle(Theme.muted)
        }
    }

    private var challenge: some View {
        Section {
            DatePicker("Day one", selection: Binding(
                get: { DayMath.date(model.s.startKey) ?? .now },
                set: { d in model.update { $0.startKey = DayMath.key(d); $0.profileDirty = true } }
            ), displayedComponents: .date)
            DatePicker("Day ends at", selection: minutes(\.settings.dayEnd), displayedComponents: .hourAndMinute)
            Button("Start a new attempt", role: .destructive) { confirmRestart = true }
        } header: {
            Text("Challenge")
        } footer: {
            Text("Set the day end after midnight if you stay up late. Anything checked before then counts for the day before.")
        }
    }

    @ViewBuilder private var friend: some View {
        Section("Friend") {
            if let f = model.them {
                HStack(spacing: 12) {
                    Avatar(image: f.avatar, name: f.name, size: 36)
                    Text(f.name).font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Text("Day \(f.currentDay(dayEnd: model.dayEnd))").foregroundStyle(Theme.muted)
                }
                Button("Remove friend", role: .destructive) { confirmRemove = true }
            }
            if !model.s.myCode.isEmpty {
                ShareLink(item: model.inviteURL, message: Text("Join my 75 Hard. Tap to add me:")) {
                    Label("Send invite link", systemImage: "paperplane")
                }
                Button {
                    UIPasteboard.general.string = model.s.myCode
                    model.show("Code copied")
                } label: {
                    Label("Copy my code", systemImage: "doc.on.doc")
                }
            }
        }
    }

    private var account: some View {
        Section {
            HStack {
                Text("Sync")
                Spacer()
                Text(model.syncProblem ?? (model.s.myCode.isEmpty ? "Waiting for iCloud" : "On"))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.trailing)
            }
            Button("Sign out", role: .destructive) { confirmSignOut = true }
        } header: {
            Text("Account")
        } footer: {
            Text("75 Hard is a program by Andy Frisella. This app is a personal tracker and is not affiliated with it.")
                .padding(.top, 8)
        }
    }

    private func minutes(_ kp: WritableKeyPath<HardState, Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(model.s[keyPath: kp]) * 60) },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                model.update { $0[keyPath: kp] = (c.hour ?? 0) * 60 + (c.minute ?? 0) }
            }
        )
    }
}

private struct ReminderRow: View {
    @EnvironmentObject var model: AppModel
    let task: HardTask

    var body: some View {
        let r = model.s.settings.reminders[task.id] ?? Reminder(on: false, minutes: 9 * 60)
        HStack(spacing: 12) {
            Image(systemName: task.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(model.accent.color)
                .frame(width: 22)
            Text(task.short)
            Spacer()
            if r.on {
                DatePicker("", selection: Binding(
                    get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(r.minutes) * 60) },
                    set: { d in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                        model.update { $0.settings.reminders[task.id] = Reminder(on: true, minutes: (c.hour ?? 0) * 60 + (c.minute ?? 0)) }
                    }
                ), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .transition(.opacity)
            }
            Toggle("", isOn: Binding(
                get: { r.on },
                set: { on in withAnimation(.smooth) { model.update { $0.settings.reminders[task.id] = Reminder(on: on, minutes: r.minutes) } } }
            ))
            .labelsHidden()
        }
    }
}

private struct NudgeSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
            Section {
                ForEach(Array(model.s.settings.nudges.enumerated()), id: \.offset) { i, m in
                    let part = DayPart(minutes: m)
                    HStack(spacing: 12) {
                        Image(systemName: part.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(model.accent.color)
                            .frame(width: 22)
                            .contentTransition(.symbolEffect(.replace))
                        Text(part.name)
                            .contentTransition(.opacity)
                        Spacer()
                        DatePicker("", selection: Binding(
                            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(m) * 60) },
                            set: { d in
                                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                                model.update { $0.settings.nudges[i] = (c.hour ?? 0) * 60 + (c.minute ?? 0) }
                            }
                        ), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    }
                }
                .onDelete { idx in model.update { $0.settings.nudges.remove(atOffsets: idx) } }
                if model.s.settings.nudges.count < 6 {
                    Button {
                        model.update { $0.settings.nudges.append(min(($0.settings.nudges.max() ?? 20 * 60) + 30, 23 * 60 + 45)) }
                    } label: {
                        Label("Add a nudge", systemImage: "plus")
                    }
                }
            } header: {
                Text("End of day nudges")
            } footer: {
                Text("Each nudge is written from the time of day and what you still have left. Once all six are done, you get one last note and then quiet.")
            }
    }
}
