import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: DiagnosticTab = .diff
    @State private var isRunningDiff = false
    @State private var isRunningBrightnessTest = false
    @State private var selectedMismatchTypes: Set<MismatchType> = Set(MismatchType.allCases)

    enum DiagnosticTab: String, CaseIterable {
        case diff = "RA2 ↔ HomeKit Diff"
        case brightness = "Brightness Test"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab Picker
            Picker("Diagnostic Type", selection: $selectedTab) {
                ForEach(DiagnosticTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            switch selectedTab {
            case .diff:
                DiffResultsView(
                    results: appState.diagnosticResults,
                    selectedTypes: $selectedMismatchTypes,
                    isRunning: isRunningDiff,
                    onRunDiff: runDiff
                )
            case .brightness:
                BrightnessTestView(
                    results: appState.brightnessTestResults,
                    isRunning: isRunningBrightnessTest,
                    onRunTest: runBrightnessTest
                )
            }
        }
        .navigationTitle("Diagnostics")
    }

    private func runDiff() async {
        isRunningDiff = true
        defer { isRunningDiff = false }

        let diagnosticService = DiagnosticService()
        let results = await diagnosticService.compareDevices(
            ra2Devices: appState.ra2Devices,
            homeKitDevices: appState.homeKitDevices
        )

        await MainActor.run {
            appState.diagnosticResults = results
        }
    }

    private func runBrightnessTest() async {
        isRunningBrightnessTest = true
        defer { isRunningBrightnessTest = false }

        let diagnosticService = DiagnosticService()
        do {
            let results = try await diagnosticService.runBulkBrightnessTest(
                devices: appState.ra2Devices,
                ra2Service: appState.ra2Service
            )
            await MainActor.run {
                appState.brightnessTestResults = results
            }
        } catch {
            await MainActor.run {
                appState.currentError = AppError(
                    title: "Brightness Test Failed",
                    message: error.localizedDescription,
                    recoveryAction: nil
                )
            }
        }
    }
}

// MARK: - Diff Results View

struct DiffResultsView: View {
    let results: [DiagnosticResult]
    @Binding var selectedTypes: Set<MismatchType>
    let isRunning: Bool
    let onRunDiff: () async -> Void

    var filteredResults: [DiagnosticResult] {
        results.filter { selectedTypes.contains($0.mismatchType) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Filter:")
                    .foregroundColor(.secondary)

                ForEach(MismatchType.allCases, id: \.self) { type in
                    Toggle(type.rawValue, isOn: Binding(
                        get: { selectedTypes.contains(type) },
                        set: { isOn in
                            if isOn {
                                selectedTypes.insert(type)
                            } else {
                                selectedTypes.remove(type)
                            }
                        }
                    ))
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button {
                    Task {
                        await onRunDiff()
                    }
                } label: {
                    if isRunning {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Label("Run Diff", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isRunning)

                Button {
                    copyResults()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(results.isEmpty)
            }
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))

            Divider()

            if results.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "No Diff Results",
                    message: "Run a diff to compare RA2 and HomeKit devices."
                )
            } else if filteredResults.isEmpty {
                EmptyStateView(
                    icon: "line.3.horizontal.decrease.circle",
                    title: "No Matches",
                    message: "No results match the current filters."
                )
            } else {
                List(filteredResults) { result in
                    DiagnosticResultRow(result: result)
                }
            }
        }
    }

    private func copyResults() {
        var csv = DiagnosticResult.csvHeader + "\n"
        for result in filteredResults {
            csv += result.csvRow + "\n"
        }
        UIPasteboard.general.string = csv
    }
}

// MARK: - Diagnostic Result Row

struct DiagnosticResultRow: View {
    let result: DiagnosticResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: result.mismatchType.icon)
                    .foregroundColor(colorForMismatchType(result.mismatchType))

                Text(result.mismatchType.rawValue)
                    .font(.headline)

                Spacer()

                Text(result.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 20) {
                if let ra2Name = result.ra2DeviceName {
                    VStack(alignment: .leading) {
                        Text("RA2")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(ra2Name)
                        if let location = result.ra2Location {
                            Text(location)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if let hkName = result.homeKitDeviceName {
                    VStack(alignment: .leading) {
                        Text("HomeKit")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(hkName)
                        if let room = result.homeKitRoom {
                            Text(room)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Text(result.details)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func colorForMismatchType(_ type: MismatchType) -> Color {
        switch type {
        case .missingFromHomeKit:
            return .orange
        case .missingFromRA2:
            return .purple
        case .nameMismatch:
            return .blue
        case .roomMismatch:
            return .yellow
        case .sceneMismatch:
            return .pink
        }
    }
}

// MARK: - Brightness Test View

struct BrightnessTestView: View {
    let results: [BrightnessTestResult]
    let isRunning: Bool
    let onRunTest: () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                VStack(alignment: .leading) {
                    Text("Brightness Diagnostic")
                        .font(.headline)
                    Text("Tests each dimmer at 100% to detect high-end trim limits")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    Task {
                        await onRunTest()
                    }
                } label: {
                    if isRunning {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Testing...")
                        }
                    } else {
                        Label("Run Test", systemImage: "waveform.badge.magnifyingglass")
                    }
                }
                .disabled(isRunning)

                Button {
                    copyResults()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(results.isEmpty)
            }
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))

            Divider()

            if results.isEmpty {
                EmptyStateView(
                    icon: "sun.max",
                    title: "No Test Results",
                    message: "Run a brightness test to check for trim limits on your dimmers."
                )
            } else {
                Table(results) {
                    TableColumn("Device") { result in
                        Text(result.device.name)
                    }

                    TableColumn("ID") { result in
                        Text("\(result.device.integrationID)")
                            .monospacedDigit()
                    }
                    .width(50)

                    TableColumn("Commanded") { result in
                        Text("\(result.commandedLevel)%")
                            .monospacedDigit()
                    }
                    .width(80)

                    TableColumn("Observed") { result in
                        Text("\(result.observedLevel)%")
                            .monospacedDigit()
                    }
                    .width(80)

                    TableColumn("Status") { result in
                        HStack {
                            Image(systemName: result.trimStatus.icon)
                                .foregroundColor(colorForTrimStatus(result.trimStatus))
                            Text(result.trimStatus.rawValue)
                        }
                    }
                    .width(150)

                    TableColumn("Notes") { result in
                        Text(result.notes)
                            .lineLimit(2)
                            .font(.caption)
                    }
                }
            }
        }
    }

    private func colorForTrimStatus(_ status: TrimStatus) -> Color {
        switch status {
        case .noTrim:
            return .green
        case .likelyTrimmed:
            return .orange
        case .unknown:
            return .gray
        }
    }

    private func copyResults() {
        var csv = BrightnessTestResult.csvHeader + "\n"
        for result in results {
            csv += result.csvRow + "\n"
        }
        UIPasteboard.general.string = csv
    }
}

#Preview {
    DiagnosticsView()
        .environmentObject(AppState())
}
