import SpaceSweepCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            ZStack {
                AuroraBackground()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if case .scanning(let progress) = model.scanState {
                    ScanProgressView(progress: progress)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(1)
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: model.isScanning)
            .navigationTitle(model.route.title)
            .navigationSubtitle(subtitle)
            .toolbar { toolbar }
        }
        .preferredColorScheme(model.appearance.colorScheme)
        .tint(Theme.accent)
        .sheet(isPresented: Binding(
            get: { model.cleanupFlow != nil },
            set: { if !$0 { model.dismissCleanupFlow() } }
        )) {
            CleanupFlowView()
                .environment(model)
                .interactiveDismissDisabled(model.isCleaning)
        }
        .alert(model.notice?.title ?? "", isPresented: Binding(
            get: { model.notice != nil },
            set: { if !$0 { model.notice = nil } }
        ), presenting: model.notice) { notice in
            if notice.offersRescan {
                Button("Rescan") { model.startScan() }
                Button("Not Now", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { notice in
            Text(notice.message)
        }
        .onAppear {
            model.applyAppearance()
            model.applyLaunchOptions()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.route {
        case .overview: OverviewView()
        case .results: ResultsView()
        case .developer: DeveloperCleanupView()
        case .activity: ActivityView()
        case .settings: SettingsView()
        }
    }

    private var subtitle: String {
        guard let volume = model.volume else {
            return model.volumeUnavailable ? "Storage unavailable" : "Reading storage…"
        }
        return "\(volume.name ?? "Startup disk") · \(Format.bytes(volume.availableBytes)) available"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if model.isScanning {
                Button {
                    model.cancelScan()
                } label: {
                    Label("Cancel Scan", systemImage: "xmark.circle")
                }
                .help("Stop the scan (⌘.)")
            } else {
                Button {
                    model.startScan()
                } label: {
                    Label("Scan", systemImage: "arrow.clockwise")
                }
                .help("Scan your Mac for known, cleanable data (⌘R)")
                .disabled(model.isCleaning)
            }
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(selection: Binding<SidebarItem?>(
            get: { model.route },
            set: { if let value = $0 { model.route = value } }
        )) {
            Section {
                ForEach([SidebarItem.overview, .results, .developer]) { item in
                    row(item)
                }
            }
            Section("Library") {
                ForEach([SidebarItem.activity, .settings]) { item in
                    row(item)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            SidebarStorageWidget()
                .padding(12)
        }
    }

    @ViewBuilder
    private func row(_ item: SidebarItem) -> some View {
        let label = Label(item.title, systemImage: item.symbol).tag(item)
        if item == .results, let report = model.report {
            label.badge(report.allCandidates.filter(\.isSelectable).count)
        } else {
            label
        }
    }
}

/// Compact live storage summary pinned to the bottom of the sidebar.
struct SidebarStorageWidget: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive.fill")
                    .foregroundStyle(Theme.brandGradient)
                Text(model.volume?.name ?? "Startup disk")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
            }
            if let volume = model.volume {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.1))
                        Capsule().fill(Theme.brandGradient)
                            .frame(width: max(4, proxy.size.width * volume.usedFraction))
                    }
                }
                .frame(height: 6)
                Text("\(Format.bytes(volume.availableBytes)) available of \(Format.bytes(volume.totalBytes))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text(model.volumeUnavailable ? "Unable to read capacity" : "Reading…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }
}
