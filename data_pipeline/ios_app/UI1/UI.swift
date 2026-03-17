//
//  ContentView.swift
//  nRFapp — TEWL Sensor App
//

import SwiftUI

// MARK: - Root

struct ContentView: View {
    @StateObject var ble = BLEManager()
    @StateObject var session = SessionManager.shared

    var body: some View {
        TabView {
            DashboardView(ble: ble, session: session)
                .tabItem { Label("Monitor", systemImage: "waveform.path.ecg") }

            SessionSetupView(ble: ble, session: session)
                .tabItem { Label("Session", systemImage: "flask") }

            DeviceView(ble: ble)
                .tabItem { Label("Device", systemImage: "antenna.radiowaves.left.and.right") }

            LogView(ble: ble)
                .tabItem { Label("Log", systemImage: "terminal") }
        }
        .tint(.teal)
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @ObservedObject var ble: BLEManager
    @ObservedObject var session: SessionManager

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {

                    // Status banner
                    StatusBanner(ble: ble, session: session)

                    // Live sensor readings
                    SensorReadingsGrid(ble: ble)

                    // Session stats
                    if session.isSessionActive {
                        SessionStatsCard(session: session)
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("TEWL Monitor")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct StatusBanner: View {
    @ObservedObject var ble: BLEManager
    @ObservedObject var session: SessionManager

    var bleColor: Color { ble.isConnected ? .teal : .orange }
    var bleLabel: String { ble.isConnected ? "Sensor Connected" : "Searching for Sensor…" }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Circle().fill(bleColor).frame(width: 10, height: 10)
                    .shadow(color: bleColor.opacity(0.6), radius: 4)
                Text(bleLabel).font(.subheadline.weight(.medium))
                Spacer()
                SessionPill(session: session)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }
}

struct SessionPill: View {
    @ObservedObject var session: SessionManager

    var body: some View {
        Group {
            if session.isSessionActive {
                Text("● RECORDING")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red)
                    .cornerRadius(20)
            } else {
                Text("No Session")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(20)
            }
        }
    }
}

struct SensorReadingsGrid: View {
    @ObservedObject var ble: BLEManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live Readings").font(.headline)

            HStack(spacing: 12) {
                MetricCard(
                    label: "Temperature",
                    value: ble.latestTemp.map { String(format: "%.2f", $0) } ?? "--",
                    unit: "°C",
                    icon: "thermometer.medium",
                    color: .orange
                )
                MetricCard(
                    label: "Humidity",
                    value: ble.latestHumidity.map { String(format: "%.1f", $0) } ?? "--",
                    unit: "%",
                    icon: "humidity",
                    color: .teal
                )
            }
            HStack(spacing: 12) {
                MetricCard(
                    label: "Pressure",
                    value: ble.latestPressure.map { String(format: "%.1f", $0) } ?? "--",
                    unit: "hPa",
                    icon: "gauge.with.dots.needle.bottom.50percent",
                    color: .indigo
                )
                MetricCard(
                    label: "TEWL",
                    value: "–",
                    unit: "g/m²h",
                    icon: "drop.triangle",
                    color: .blue,
                    note: "Model pending"
                )
            }
        }
    }
}

struct MetricCard: View {
    let label: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon).foregroundColor(color)
                Text(label).font(.caption).foregroundColor(.secondary)
            }
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundColor(value == "--" ? .secondary : .primary)
                Text(unit).font(.caption).foregroundColor(.secondary)
            }
            if let note = note {
                Text(note).font(.caption2).foregroundColor(Color.secondary.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }
}

struct SessionStatsCard: View {
    @ObservedObject var session: SessionManager

    var elapsed: String {
        guard let s = session.currentSession?.start_time,
              let date = ISO8601DateFormatter().date(from: s) else { return "--" }
        let secs = Int(Date().timeIntervalSince(date))
        return String(format: "%02d:%02d:%02d", secs / 3600, (secs % 3600) / 60, secs % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Stats").font(.headline)

            HStack {
                StatItem(label: "Readings", value: "\(session.uploadCount)")
                Divider()
                StatItem(label: "Subject", value: session.currentSession?.subject_id ?? "–")
                Divider()
                StatItem(label: "Site", value: session.currentSession?.body_site ?? "–")
            }
            .frame(height: 50)
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(14)
        }
    }
}

struct StatItem: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.body, design: .rounded).weight(.semibold))
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Session Setup

struct SessionSetupView: View {
    @ObservedObject var ble: BLEManager
    @ObservedObject var session: SessionManager

    @State private var showError = false
    @State private var errorMsg = ""

    var body: some View {
        NavigationView {
            Form {
                if session.isSessionActive {
                    // Active session info
                    Section("Active Session") {
                        if let s = session.currentSession {
                            LabeledContent("Session ID", value: String(s.session_id.prefix(8)) + "…")
                            if let site = s.body_site { LabeledContent("Body Site", value: site) }
                            if let cond = s.condition_label { LabeledContent("Condition", value: cond) }
                            if let subj = s.subject_id { LabeledContent("Subject", value: subj) }
                        }
                        LabeledContent("Readings Sent", value: "\(session.uploadCount)")
                    }

                    Section {
                        Button(role: .destructive) { session.endSession() } label: {
                            HStack {
                                Spacer()
                                Text("End Session")
                                Spacer()
                            }
                        }
                    }

                } else {
                    // New session form
                    Section("Participant") {
                        TextField("Subject ID (e.g. P001)", text: $session.subjectId)
                            .autocorrectionDisabled()
                    }

                    Section("Measurement Site") {
                        Picker("Body Site", selection: $session.bodySite) {
                            Text("Select…").tag("")
                            ForEach(SessionManager.bodySiteOptions, id: \.self) { site in
                                Text(site).tag(site)
                            }
                        }
                    }

                    Section("Condition") {
                        Picker("Condition", selection: $session.conditionLabel) {
                            Text("Select…").tag("")
                            ForEach(SessionManager.conditionOptions, id: \.self) { c in
                                Text(c).tag(c)
                            }
                        }
                    }

                    Section("Notes") {
                        TextField("Optional notes…", text: $session.note, axis: .vertical)
                            .lineLimit(3...)
                    }

                    Section {
                        if case .creating = session.state {
                            HStack {
                                Spacer()
                                ProgressView("Creating session…")
                                Spacer()
                            }
                        } else {
                            Button {
                                startSession()
                            } label: {
                                HStack {
                                    Spacer()
                                    Label("Start Recording", systemImage: "record.circle")
                                        .font(.headline)
                                    Spacer()
                                }
                            }
                            .tint(.teal)
                        }
                    }

                    if case .error(let msg) = session.state {
                        Section {
                            Text(msg).foregroundColor(.red).font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Experiment Session")
        }
    }

    private func startSession() {
        session.startSession { success in
            if !success, case .error(let msg) = session.state {
                errorMsg = msg
                showError = true
            }
        }
    }
}

// MARK: - Device

struct DeviceView: View {
    @ObservedObject var ble: BLEManager
    @State private var outbound = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Device list
                if !ble.isConnected {
                    List(ble.peripherals) { p in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(p.name).font(.headline)
                                Text("RSSI: \(p.rssi) dBm").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Connect") { ble.connectPeripheral(p.peripheral) }
                                .buttonStyle(.borderedProminent)
                                .tint(.teal)
                                .controlSize(.small)
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.teal)
                        Text("Sensor Connected")
                            .font(.title2.weight(.semibold))
                        Button("Disconnect") { ble.disconnect() }
                            .buttonStyle(.bordered)
                            .tint(.red)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 200)

                    Divider()

                    // Manual send (for debugging firmware)
                    HStack {
                        TextField("Send command…", text: $outbound)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                        Button("Send") {
                            ble.send(text: outbound)
                            outbound = ""
                        }
                        .disabled(!ble.isConnected || outbound.isEmpty)
                    }
                    .padding()
                    Spacer()
                }
            }
            .navigationTitle("Device")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !ble.isConnected {
                        Button { ble.startScanning() } label: {
                            Label("Scan", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Log

struct LogView: View {
    @ObservedObject var ble: BLEManager

    var body: some View {
        NavigationView {
            List(ble.logLines.reversed(), id: \.self) { line in
                Text(line)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(logColor(line))
            }
            .navigationTitle("Debug Log")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") { ble.logLines.removeAll() }
                }
            }
        }
    }

    func logColor(_ line: String) -> Color {
        if line.contains("⚠️") || line.contains("error") || line.contains("Error") { return .orange }
        if line.contains("←") { return .teal }
        if line.contains("→") { return .blue }
        if line.contains("Parsed") { return .green }
        return .primary
    }
}
