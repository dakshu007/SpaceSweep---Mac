import SpaceSweepCore
import SwiftUI

/// Full-detail overlay shown while a scan runs. Every number here comes from the scanner.
struct ScanProgressView: View {
    @Environment(AppModel.self) private var model
    let progress: ScanProgress

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 26) {
                SweepRadar(size: 210)
                VStack(spacing: 6) {
                    Text("Scanning your Mac")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(progress.currentRuleTitle.map { "\(progress.phase.title) · \($0)" } ?? progress.phase.title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: progress.currentRuleTitle)
                }
                HStack(spacing: 14) {
                    counter(value: progress.examinedItems.formatted(), label: "items examined", symbol: "doc.on.doc")
                    counter(value: Format.bytes(progress.measuredBytes), label: "measured", symbol: "scalemass")
                    counter(value: progress.candidatesFound.formatted(), label: "candidates", symbol: "sparkles")
                }
                PhaseChecklist(current: progress.phase)
                Button(role: .cancel) {
                    model.cancelScan()
                } label: {
                    Text("Cancel Scan").frame(minWidth: 120)
                }
                .buttonStyle(.secondary)
                .keyboardShortcut(.cancelAction)
            }
            .padding(36)
            .frame(maxWidth: 560)
            .card(padding: 0, radius: 28)
            .padding(40)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scan in progress")
    }

    private func counter(value: String, label: String, symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(Theme.brandGradient)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }
}

struct PhaseChecklist: View {
    let current: ScanPhase

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(ScanPhase.allCases, id: \.self) { phase in
                HStack(spacing: 10) {
                    ZStack {
                        if phase < current {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.mint)
                                .transition(.scale.combined(with: .opacity))
                        } else if phase == current {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: 18, height: 18)
                    Text(phase.title)
                        .font(.callout.weight(phase == current ? .semibold : .regular))
                        .foregroundStyle(phase > current ? Color.secondary : Color.primary)
                    Spacer()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(phase.title)
                .accessibilityValue(phase < current ? "Done" : (phase == current ? "In progress" : "Pending"))
            }
        }
        .animation(.snappy, value: current)
        .padding(.horizontal, 8)
    }
}
