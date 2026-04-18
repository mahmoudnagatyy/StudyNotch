import SwiftUI

struct PinManagerPopover: View {
    @Binding var pinnedSubjects: [String]
    @Bindable var modeStore = ModeStore.shared
    @Bindable var subjectStore = SubjectStore.shared
    @State private var manualSubjects: [String] = {
        if let saved = UserDefaults.standard.stringArray(forKey: "notch.manualSubjects") {
            return saved
        }
        if let legacy = UserDefaults.standard.stringArray(forKey: "notch.allSubjects") {
            return legacy
        }
        return []
    }()
    @State private var hiddenSubjects: Set<String> = {
        let saved = UserDefaults.standard.stringArray(forKey: "notch.hiddenSubjects") ?? []
        return Set(saved)
    }()
    @State private var newSubjectName = ""

    var semesterSubjects: [String] {
        modeStore.collegeSubjects.map(\.name)
    }

    var allSubjects: [String] {
        let merged = Array(Set(semesterSubjects + manualSubjects))
        return merged
            .filter { !hiddenSubjects.contains(normalized($0)) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notch Subjects")
                .font(.headline)

            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill").foregroundColor(.green)
                TextField("New subject...", text: $newSubjectName)
                    .textFieldStyle(.plain)
                    .onSubmit { add() }
                Spacer()
                Button("Add") { add() }
                    .foregroundColor(.green)
            }
            .padding(6)
            .background(Color.white.opacity(0.1))
            .cornerRadius(6)

            if pinnedSubjects.isEmpty {
                Text("Nothing pinned. Pin subjects below to add them to the quick-select strip.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Text("ALL SUBJECTS")
                .font(.caption2).fontWeight(.bold)
                .foregroundColor(.secondary)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(allSubjects.enumerated()), id: \.offset) { _, sub in
                        let isPinned = containsNormalized(pinnedSubjects, sub)
                        HStack(spacing: 8) {
                            Circle().fill(subjectStore.color(for: sub)).frame(width: 8, height: 8)
                            Text(sub).font(.system(size: 13))
                            Spacer()
                            Button {
                                if isPinned {
                                    pinnedSubjects.removeAll { normalized($0) == normalized(sub) }
                                } else {
                                    pinnedSubjects.append(sub)
                                }
                                savePinned()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "pin.fill")
                                    Text(isPinned ? "Unpin" : "Pin")
                                        .font(.caption)
                                }
                                .foregroundColor(isPinned ? .orange : .green)
                            }
                            .buttonStyle(.plain)

                            Button(role: .destructive) {
                                deleteSubject(sub)
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .font(.caption)
                                    .foregroundColor(.red.opacity(0.8))
                                    .frame(height: 24)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding()
        .frame(width: 280)
    }

    func add() {
        let n = newSubjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        let key = normalized(n)
        hiddenSubjects.remove(key)
        if !containsNormalized(manualSubjects, n) {
            manualSubjects.append(n)
            saveManualSubjects()
        }
        if !containsNormalized(pinnedSubjects, n) {
            pinnedSubjects.append(n)
            savePinned()
        }
        saveHiddenSubjects()
        subjectStore.ensureMeta(for: n)
        newSubjectName = ""
    }

    func savePinned() {
        UserDefaults.standard.set(pinnedSubjects, forKey: "notch.pinnedSubjects")
    }

    func saveManualSubjects() {
        UserDefaults.standard.set(manualSubjects, forKey: "notch.manualSubjects")
        UserDefaults.standard.set(manualSubjects, forKey: "notch.allSubjects")
    }

    func saveHiddenSubjects() {
        UserDefaults.standard.set(Array(hiddenSubjects), forKey: "notch.hiddenSubjects")
    }

    func deleteSubject(_ name: String) {
        let key = normalized(name)
        manualSubjects.removeAll { normalized($0) == key }
        hiddenSubjects.insert(key)
        pinnedSubjects.removeAll { normalized($0) == key }
        saveManualSubjects()
        saveHiddenSubjects()
        savePinned()
        if normalized(StudyTimer.shared.currentSubject) == key {
            StudyTimer.shared.currentSubject = ""
        }
    }

    private func containsNormalized(_ values: [String], _ value: String) -> Bool {
        let key = normalized(value)
        return values.contains { normalized($0) == key }
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
