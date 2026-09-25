import SwiftUI

/// Large tap target that launches one navigation app.
struct NavigationButton: View {
    let app: NavigationApp
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: app.symbolName).font(.title3)
                Text(app.displayName).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(.white)
            .background(app.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Navigate with \(app.accessibilityName)")
    }
}
