import SpaceSweepCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var detailRule: CleanupRule?

    var body: some View {
        @Bindable var model = model

        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $model.appearance) {
                    ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Toggle(isOn: $model.oneClickEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("One-click Safe Clean")
                        Text("Lets the main button scan and clean Safe items without a second confirmation. It never includes Review or Protected items, or the Trash. Requires one confirmed cleanup first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if model.oneClickEnabled && !model.hasConfirmedFirstClean {
                    Label("Confirm one cleanup from Scan Results to activate.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if model.hasConfirmedFirstClean {
                    Button("Show the confirmation summary again next time") { model.hasConfirmedFirstClean = false }
                }
                Toggle(isOn: $model.recordPathsInActivity) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Record paths in activity")
                        Text("Off by default. When on, paths of items that weren’t removed are saved locally (home shown as ~) to help diagnose failures.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Safety")
            }

            Section {
                ForEach(model.registry.rules) { rule in
                    HStack(spacing: 12) {
                        IconTile(symbol: rule.symbolName, color: Theme.color(for: rule.category), size: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(rule.title)
                                SafetyBadge(tier: rule.tier, compact: true)
                            }
                            Text(rule.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button {
                            detailRule = rule
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(GhostIconButtonStyle())
                        .help("Rule rationale")
                        Toggle("Enabled", isOn: Binding(
                            get: { model.isRuleEnabled(rule) },
                            set: { model.setRule(rule, enabled: $0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("Scan \(rule.title)")
                    }
                }
            } header: {
                Text("Cleanup rules")
            } footer: {
                Text("Only Safe rules are selected automatically. Turning a rule off stops SpaceSweep from looking there at all.")
            }

            Section("Permissions") {
                HStack(spacing: 12) {
                    Image(systemName: model.fullDiskAccess == .granted ? "checkmark.shield.fill" : "lock.shield")
                        .font(.title2)
                        .foregroundStyle(model.fullDiskAccess == .granted ? Theme.mint : Theme.indigo)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.fullDiskAccess.title)
                        Text("Optional. SpaceSweep reads its rule folders with your normal permissions. Full Disk Access only lets it measure privacy-protected locations such as the Trash and device backups — it never makes protected files deletable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(PermissionService.fullDiskAccessInstructions)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Open Privacy & Security…") { model.openFullDiskAccessSettings() }
                    Button("Check Again") { model.refreshPermissions() }
                }
                Text("SpaceSweep never asks for an administrator password and never runs privileged helpers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                LabeledContent("Last scan") {
                    Text(model.lastScanDate.map { Format.dateTime($0) } ?? "Never")
                }
                Button("Clear Scan Results") { model.clearScanResults() }
                    .disabled(model.report == nil && model.lastScanDate == nil)
                Text("Clears SpaceSweep’s own scan data only. Nothing on disk is affected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Label("All scan results remain on this Mac. No telemetry or network connection is used.", systemImage: "hand.raised.fill")
            }

            Section("About") {
                LabeledContent("Version", value: model.appVersion)
                LabeledContent("Bundle identifier", value: Bundle.main.bundleIdentifier ?? "app.spacesweep.mac")
                LabeledContent("Build type", value: "Personal build · not notarized")
                LabeledContent("Architecture", value: architecture)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity)
        .sheet(item: $detailRule) { rule in
            RuleDetailSheet(rule: rule, result: model.report?.result(for: rule.id))
                .environment(model)
        }
        .onAppear { model.refreshPermissions() }
    }

    private var architecture: String {
        #if arch(arm64)
        return "Apple silicon (arm64)"
        #else
        return "Intel (x86_64)"
        #endif
    }
}
