import SwiftUI

// MARK: - Data Model

struct BlissScheduleEntry: Codable, Identifiable {
    var id = UUID()
    var configName: String
    var days: Set<Int>          // 1=Sun, 2=Mon, ..., 7=Sat
    var hour: Int               // 0-23
    var minute: Int             // 0-59
    var durationMinutes: Int    // session length
    var enabled: Bool = true
}

// MARK: - Persistence

enum BlissScheduleManager {
    private static func schedulesURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss/schedules.json")
    }

    static func load() -> [BlissScheduleEntry] {
        let url = schedulesURL()
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([BlissScheduleEntry].self, from: data) else {
            return []
        }
        return entries
    }

    static func save(_ entries: [BlissScheduleEntry]) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = schedulesURL()
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url)
    }
}

// MARK: - Schedule View

struct ScheduleView: View {
    @EnvironmentObject var vm: BlissViewModel
    @State private var showAddSheet = false
    @State private var editingEntry: BlissScheduleEntry?
    @State private var prefillDay: Int?
    @State private var prefillHour: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if vm.schedules.isEmpty {
                    emptyState
                } else {
                    scheduleList
                    weeklyGrid
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showAddSheet) {
            ScheduleEditSheet(
                entry: nil,
                configs: vm.profiles,
                prefillDay: prefillDay,
                prefillHour: prefillHour
            ) { entry in
                vm.addSchedule(entry)
            }
        }
        .sheet(item: $editingEntry) { entry in
            ScheduleEditSheet(
                entry: entry,
                configs: vm.profiles,
                onSave: { updated in
                    vm.updateSchedule(updated)
                },
                onDelete: { id in
                    vm.deleteSchedule(id: id)
                }
            )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No scheduled sessions")
                .font(.title2.weight(.semibold))
            Text("Automatically start focus sessions on a weekly schedule tied to your saved configs.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button {
                prefillDay = nil
                prefillHour = nil
                showAddSheet = true
            } label: {
                Label("Add Schedule", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }

    // MARK: - Schedule List

    private var scheduleList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Schedules")
                    .font(.headline)
                Spacer()
                Button {
                    prefillDay = nil
                    prefillHour = nil
                    showAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .controlSize(.small)
            }

            ForEach(vm.schedules) { entry in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(colorForConfig(entry.configName))
                        .frame(width: 4, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(entry.configName)
                                .font(.callout.weight(.medium))
                            Text(daysText(entry.days))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text("\(formatTime(entry.hour, entry.minute)) - \(formatEndTime(entry.hour, entry.minute, entry.durationMinutes))  (\(entry.durationMinutes)m)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { entry.enabled },
                        set: { newValue in
                            var updated = entry
                            updated.enabled = newValue
                            vm.updateSchedule(updated)
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Button {
                        editingEntry = entry
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)

                    Button {
                        vm.deleteSchedule(id: entry.id)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Weekly Grid

    private let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private let columnToWeekday = [2, 3, 4, 5, 6, 7, 1]
    private let rowHeight: CGFloat = 22
    private let headerHeight: CGFloat = 28

    private var weeklyGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekly Overview")
                .font(.headline)

            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    // Hour labels column
                    VStack(spacing: 0) {
                        Color.clear.frame(height: headerHeight)
                        ForEach(0..<24, id: \.self) { hour in
                            Text(formatHour(hour))
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .frame(width: 32, height: rowHeight, alignment: .topTrailing)
                                .padding(.trailing, 3)
                        }
                    }

                    // Day columns
                    ForEach(0..<7, id: \.self) { col in
                        let weekday = columnToWeekday[col]
                        VStack(spacing: 0) {
                            Text(dayLabels[col])
                                .font(.system(size: 10, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .frame(height: headerHeight)

                            ZStack(alignment: .topLeading) {
                                VStack(spacing: 0) {
                                    ForEach(0..<24, id: \.self) { hour in
                                        Rectangle()
                                            .fill(Color.primary.opacity(hour % 2 == 0 ? 0.03 : 0.06))
                                            .frame(height: rowHeight)
                                            .overlay(
                                                Rectangle()
                                                    .fill(Color.primary.opacity(0.08))
                                                    .frame(height: 0.5),
                                                alignment: .top
                                            )
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                prefillDay = weekday
                                                prefillHour = hour
                                                showAddSheet = true
                                            }
                                    }
                                }

                                ForEach(blocksForDay(weekday)) { block in
                                    scheduleBlock(block)
                                }
                            }
                        }
                    }
                }
            }
            .frame(height: 24.0 * rowHeight + headerHeight)
            .background(Color(.controlBackgroundColor).opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private struct GridBlock: Identifiable {
        let id: UUID
        let entry: BlissScheduleEntry
        let topOffset: CGFloat
        let height: CGFloat
        let color: Color
    }

    private func blocksForDay(_ weekday: Int) -> [GridBlock] {
        vm.schedules
            .filter { $0.enabled && $0.days.contains(weekday) }
            .map { entry in
                let startMinutes = entry.hour * 60 + entry.minute
                let topOffset = CGFloat(startMinutes) / 60.0 * rowHeight
                let height = max(CGFloat(entry.durationMinutes) / 60.0 * rowHeight, 14)
                return GridBlock(
                    id: entry.id,
                    entry: entry,
                    topOffset: topOffset,
                    height: height,
                    color: colorForConfig(entry.configName)
                )
            }
    }

    private func scheduleBlock(_ block: GridBlock) -> some View {
        Button {
            editingEntry = block.entry
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(block.entry.configName)
                    .font(.system(size: 8, weight: .semibold))
                    .lineLimit(1)
                if block.height > 18 {
                    Text(formatTime(block.entry.hour, block.entry.minute))
                        .font(.system(size: 7))
                        .lineLimit(1)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: block.height)
            .background(block.color, in: RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .offset(y: block.topOffset)
        .padding(.horizontal, 1)
    }

    // MARK: - Helpers

    private func colorForConfig(_ name: String) -> Color {
        // Use the profile's chosen color if available
        if let profile = vm.profiles.first(where: { $0.name == name }) {
            return profile.color
        }
        // Fallback for orphaned schedule entries
        let palette: [Color] = [.blue, .purple, .orange, .green, .pink, .cyan, .indigo, .mint]
        let hash = abs(name.hashValue)
        return palette[hash % palette.count]
    }

    private func formatHour(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let ampm = hour < 12 ? "a" : "p"
        return "\(h)\(ampm)"
    }

    private func formatTime(_ hour: Int, _ minute: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let ampm = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", h, minute, ampm)
    }

    private func formatEndTime(_ hour: Int, _ minute: Int, _ duration: Int) -> String {
        let totalMinutes = hour * 60 + minute + duration
        let endHour = (totalMinutes / 60) % 24
        let endMinute = totalMinutes % 60
        return formatTime(endHour, endMinute)
    }

    private func daysText(_ days: Set<Int>) -> String {
        let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let order = [2, 3, 4, 5, 6, 7, 1]
        let sorted = order.filter { days.contains($0) }
        if sorted.count == 7 { return "Every day" }
        if sorted == [2, 3, 4, 5, 6] { return "Weekdays" }
        if sorted == [1, 7] { return "Weekends" }
        return sorted.map { names[$0] }.joined(separator: ", ")
    }
}

// MARK: - Add/Edit Sheet

struct ScheduleEditSheet: View {
    let entry: BlissScheduleEntry?
    let configs: [BlissProfile]
    var prefillDay: Int? = nil
    var prefillHour: Int? = nil
    let onSave: (BlissScheduleEntry) -> Void
    var onDelete: ((UUID) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var configName: String = ""
    @State private var selectedDays: Set<Int> = []
    @State private var displayHour: Int = 9   // 1-12
    @State private var selectedMinute: Int = 0
    @State private var isAM: Bool = true
    @State private var durationHours: Int = 1
    @State private var durationMins: Int = 0

    /// Convert 12h display + AM/PM to 24h
    private var selectedHour24: Int {
        var h = displayHour
        if h == 12 { h = 0 }
        if !isAM { h += 12 }
        return h
    }

    private let dayButtons: [(label: String, weekday: Int)] = [
        ("M", 2), ("T", 3), ("W", 4), ("T", 5), ("F", 6), ("S", 7), ("S", 1)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(entry == nil ? "Add Schedule" : "Edit Schedule")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            // Form
            VStack(alignment: .leading, spacing: 20) {
                // Config picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Config")
                        .font(.callout.weight(.medium))
                    if configs.isEmpty {
                        Text("Save a config first in Settings")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        Picker("", selection: $configName) {
                            Text("Select a config").tag("")
                            ForEach(configs) { config in
                                HStack {
                                    Circle().fill(config.color).frame(width: 8, height: 8)
                                    Text(config.name)
                                }
                                .tag(config.name)
                            }
                        }
                        .labelsHidden()
                    }
                }

                // Day picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Days")
                        .font(.callout.weight(.medium))
                    HStack(spacing: 6) {
                        ForEach(dayButtons, id: \.weekday) { day in
                            let selected = selectedDays.contains(day.weekday)
                            Button {
                                if selected {
                                    selectedDays.remove(day.weekday)
                                } else {
                                    selectedDays.insert(day.weekday)
                                }
                            } label: {
                                Text(day.label)
                                    .font(.system(size: 13, weight: .medium))
                                    .frame(width: 36, height: 36)
                                    .background(
                                        selected ? Color.accentColor : Color.primary.opacity(0.08),
                                        in: Circle()
                                    )
                                    .foregroundColor(selected ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Circle())
                        }
                    }
                }

                // Start time - stepper digits with AM/PM
                VStack(alignment: .leading, spacing: 6) {
                    Text("Start Time")
                        .font(.callout.weight(.medium))
                    HStack(spacing: 0) {
                        timeDigitPicker(value: $displayHour, range: Array(1...12), format: "%d")
                        Text(":")
                            .font(.system(size: 28, weight: .medium, design: .rounded))
                            .padding(.horizontal, 2)
                        timeDigitPicker(value: $selectedMinute, range: Array(stride(from: 0, to: 60, by: 5)), format: "%02d")

                        // AM/PM toggle
                        VStack(spacing: 2) {
                            Button {
                                isAM = true
                            } label: {
                                Text("AM")
                                    .font(.system(size: 12, weight: isAM ? .bold : .regular))
                                    .foregroundColor(isAM ? .accentColor : .secondary)
                                    .frame(width: 36, height: 20)
                                    .background(isAM ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)

                            Button {
                                isAM = false
                            } label: {
                                Text("PM")
                                    .font(.system(size: 12, weight: !isAM ? .bold : .regular))
                                    .foregroundColor(!isAM ? .accentColor : .secondary)
                                    .frame(width: 36, height: 20)
                                    .background(!isAM ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.leading, 8)

                        Spacer()
                    }
                }

                // Duration - stepper digits
                VStack(alignment: .leading, spacing: 6) {
                    Text("Duration")
                        .font(.callout.weight(.medium))
                    HStack(spacing: 4) {
                        timeDigitPicker(value: $durationHours, range: 0..<9, format: "%d")
                        Text("h")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                        timeDigitPicker(value: $durationMins, range: Array(stride(from: 0, to: 60, by: 5)), format: "%02d")
                        Text("m")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
            .padding(20)

            Spacer()
            Divider()

            // Footer
            HStack {
                if let entry = entry, let onDelete = onDelete {
                    Button(role: .destructive) {
                        dismiss()
                        onDelete(entry.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                Spacer()
                Button("Save") {
                    saveEntry()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(configName.isEmpty || selectedDays.isEmpty || totalDuration < 5)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 400, height: 560)
        .onAppear {
            if let existing = entry {
                configName = existing.configName
                selectedDays = existing.days
                let (h12, am) = to12Hour(existing.hour)
                displayHour = h12
                isAM = am
                selectedMinute = existing.minute
                durationHours = existing.durationMinutes / 60
                durationMins = existing.durationMinutes % 60
            } else {
                configName = configs.first?.name ?? ""
                if let day = prefillDay {
                    selectedDays = [day]
                }
                if let hour = prefillHour {
                    let (h12, am) = to12Hour(hour)
                    displayHour = h12
                    isAM = am
                    selectedMinute = 0
                }
            }
        }
    }

    /// A tappable digit display with up/down stepper arrows and inline editing
    private func timeDigitPicker(value: Binding<Int>, range: [Int], format: String) -> some View {
        TimeDigitPickerView(value: value, range: range, format: format)
    }

    private func timeDigitPicker(value: Binding<Int>, range: Range<Int>, format: String) -> some View {
        TimeDigitPickerView(value: value, range: Array(range), format: format)
    }

    private var totalDuration: Int {
        durationHours * 60 + durationMins
    }

    private func to12Hour(_ h24: Int) -> (hour12: Int, am: Bool) {
        let am = h24 < 12
        var h = h24 % 12
        if h == 0 { h = 12 }
        return (h, am)
    }

    private func saveEntry() {
        var result = entry ?? BlissScheduleEntry(
            configName: configName,
            days: selectedDays,
            hour: selectedHour24,
            minute: selectedMinute,
            durationMinutes: totalDuration
        )
        result.configName = configName
        result.days = selectedDays
        result.hour = selectedHour24
        result.minute = selectedMinute
        result.durationMinutes = max(5, min(480, totalDuration))

        onSave(result)
    }
}

// MARK: - Time Digit Picker

struct TimeDigitPickerView: View {
    @Binding var value: Int
    let range: [Int]
    let format: String

    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var fieldFocused: Bool

    private var idx: Int {
        range.firstIndex(of: value) ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                let next = (idx + 1) % range.count
                value = range[next]
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 48, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ZStack {
                if isEditing {
                    TextField("", text: $editText)
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .frame(width: 48)
                        .focused($fieldFocused)
                        .onSubmit { commitEdit() }
                        .onChange(of: editText) {
                            editText = String(editText.filter { $0.isNumber }.prefix(3))
                        }
                } else {
                    Text(String(format: format, value))
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 48)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editText = ""
                            isEditing = true
                            fieldFocused = true
                        }
                }
            }

            Button {
                let prev = (idx - 1 + range.count) % range.count
                value = range[prev]
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 48, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: fieldFocused) {
            if !fieldFocused && isEditing {
                commitEdit()
            }
        }
    }

    private func commitEdit() {
        isEditing = false
        guard let typed = Int(editText), !editText.isEmpty else { return }
        // Find the closest value in range
        if let exact = range.first(where: { $0 == typed }) {
            value = exact
        } else if let closest = range.min(by: { abs($0 - typed) < abs($1 - typed) }) {
            value = closest
        }
    }
}
