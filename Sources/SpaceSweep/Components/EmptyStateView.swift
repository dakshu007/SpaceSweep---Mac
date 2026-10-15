import SwiftUI

struct EmptyStateView<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.brandGradient).opacity(0.15).frame(width: 110, height: 110)
                Circle().strokeBorder(Theme.brandGradient, lineWidth: 1).opacity(0.35).frame(width: 110, height: 110)
                Image(systemName: symbol)
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(Theme.brandGradient)
            }
            VStack(spacing: 6) {
                Text(title).font(.title2.weight(.semibold))
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            HStack(spacing: 12) { actions() }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(symbol: String, title: String, message: String) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}
