import SwiftUI

/// Pill that launches one navigation app. Prominent pills (the next or current stop) are
/// filled with the app's color; the rest are tinted so the featured stop stands out.
struct NavigationButton: View {
    let app: NavigationApp
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: app.symbolName)
                    .foregroundStyle(isProminent ? .white : app.tint)
                Text(app.displayName)
                    .foregroundStyle(isProminent ? .white : .primary)
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                if isProminent {
                    Capsule()
                        .fill(LinearGradient(colors: [app.tint.opacity(0.85), app.tint],
                                             startPoint: .top, endPoint: .bottom))
                        .shadow(color: app.tint.opacity(0.35), radius: 8, y: 4)
                } else {
                    Capsule().fill(app.tint.opacity(0.14))
                }
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Navigate with \(app.accessibilityName)")
    }
}

/// Shrinks slightly while pressed.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
