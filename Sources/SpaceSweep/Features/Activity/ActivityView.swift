import AppKit
import SpaceSweepCore
import SwiftUI
import UniformTypeIdentifiers

struct ActivityView: View {
    @Environment(AppModel.self) private var model
    @State private var expanded: Set<UUID> = []
    @State private var confirmClear = false
    @State private var showExport = false
    @State private var includePaths = false

    var body: some View {
        Group {
            if model.activity.isEmpty {
                EmptyStateView(symbol: "clock.arrow.circlepath", title: "No activity yet",
                               message: "Scans and cleanups are recorded here, on this Mac only. Paths aren’t stored unless you turn that on in Settings.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Label("Stored only on this Mac", systemImage: "lock.fill")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.bottom, 16)
                        ForEach(Array(model.activity.enumerated()), id: \.element.id) { index, entry in
                            ActivityRow(entry: entry,
                                        isLast: index == model.activity.count - 1,
                                        isExpanded: expanded.contains(entry.id)) {
                                if expanded.contains(entry.id) { expanded.remove(entry.id) } else { expanded.insert(entry.id) }
                            }
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    showExport = true
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                .help("Save a diagnostic text file")
                .disabled(model.activity.isEmpty)
                Button(role: .destructive) {
                    confirmClear = true
                } label: {
                    Label("Clear History", systemImage: "trash")
                }
                .help("Clear SpaceSweep’s own history")
                .disabled(model.activity.isEmpty)
            }
        }
        .confirmationDialog("Clear SpaceSweep’s activity history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { model.clearActivity() }
        } message: {
            Text("This removes only SpaceSweep’s own log. It doesn’t affect any files on your Mac.")
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(includePaths: $includePaths) { export() }
        }
    }

    private func export() {
        let text = ActivityLogService.exportText(model.activity, includePaths: includePaths, appVersion: model.appVersion)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "SpaceSweep Activity.txt"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                model.notice = .init(title: "Export failed", message: "The file couldn’t be saved.")
            }
        }
    }
}

private struct ExportSheet: View {
    @Binding var includePaths: Bool
    let onExport: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export diagnostics").font(.title2.weight(.bold))
            Text("Creates a plain-text file you can inspect or share yourself. Nothing is uploaded.")
                .foregroundStyle(.secondary)
            Toggle("Include paths in diagnostic export", isOn: $includePaths)
                .toggleStyle(.checkbox)
            Text("Paths are only available for entries recorded while “Record paths in activity” was on in Settings. Home is shown as ~.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                Button("Export…") {
                    dismiss()
                    DispatchQueue.main.async { onExport() }
                }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

private struct ActivityRow: View {
    let entry: ActivityEntry
    let isLast: Bool
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(color.opacity(0.15)).frame(width: 34, height: 34)
                    Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(color)
                }
                if !isLast {
                    Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.title).font(.headline)
                        Text(Format.dateTime(entry.date)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if entry.kind == .scan {
                            Text(Format.bytes(entry.estimatedBytes)).font(.callout.weight(.semibold)).monospacedDigit()
                            Text("found").font(.caption).foregroundStyle(.secondary)
                        } else if let change = entry.measuredFreeSpaceChange {
                            Text("+\(Format.bytes(change))").font(.callout.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.mint)
                            Text("free space measured").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("≈ \(Format.bytes(entry.bytesRemoved))").font(.callout.weight(.semibold)).monospacedDigit()
                            Text("of files removed").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Text(entry.detail).font(.callout).foregroundStyle(.secondary)
                if !entry.rules.isEmpty {
                    Button(isExpanded ? "Hide details" : "Show details", action: toggle)
                        .buttonStyle(.link)
                        .font(.caption)
                    if isExpanded {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(entry.rules) { line in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(line.title).font(.callout.weight(.medium))
                                        Spacer()
                                        Text("\(line.deleted) removed · \(line.failed) failed · \(line.skipped) skipped")
                                            .font(.caption).foregroundStyle(.secondary)
                                        Text(Format.bytes(line.bytesRemoved)).font(.caption.weight(.semibold)).monospacedDigit()
                                            .frame(minWidth: 64, alignment: .trailing)
                                    }
                                    ForEach(line.problems, id: \.self) { problem in
                                        Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.amber)
                                    }
                                }
                            }
                            if let paths = entry.paths, !paths.isEmpty {
                                Divider()
                                Text("Items not removed").font(.caption.weight(.semibold))
                                ForEach(paths, id: \.self) { path in
                                    Text(path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
                    }
                }
            }
            .card(padding: 16, radius: Theme.rowRadius)
            .padding(.bottom, 14)
        }
    }

    private var color: Color {
        switch entry.status {
        case .success: return Theme.mint
        case .partial, .cancelled: return Theme.amber
        case .failed: return Theme.amber
        case .info: return Theme.slate
        }
    }

    private var symbol: String {
        switch entry.kind {
        case .scan: return "sparkle.magnifyingglass"
        case .dryRun: return "testtube.2"
        case .cleanup:
            switch entry.status {
            case .success: return "checkmark"
            case .cancelled: return "stop.fill"
            case .failed: return "xmark"
            default: return "exclamationmark"
            }
        }
    }
}
