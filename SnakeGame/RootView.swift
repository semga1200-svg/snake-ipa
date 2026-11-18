import SwiftUI

enum AppTab: Int, CaseIterable, Identifiable {
    case snake, jailbreak, downgrade

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .snake: return "Змейка"
        case .jailbreak: return "Джейл"
        case .downgrade: return "Откат"
        }
    }

    var icon: String {
        switch self {
        case .snake: return "gamecontroller.fill"
        case .jailbreak: return "terminal.fill"
        case .downgrade: return "arrow.uturn.down.circle.fill"
        }
    }
}

struct RootView: View {
    @State private var tab: AppTab = .snake
    @State private var previousTab: AppTab = .snake
    @Namespace private var ns

    var body: some View {
        ZStack {
            GlassBackground()

            VStack(spacing: 0) {
                content
                Spacer(minLength: 96)
            }

            VStack {
                Spacer()
                tabBar
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            switch tab {
            case .snake: SnakeScreen().transition(transition)
            case .jailbreak: JailbreakScreen().transition(transition)
            case .downgrade: DowngradeScreen().transition(transition)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: tab)
    }

    private var transition: AnyTransition {
        let forward = tab.rawValue > previousTab.rawValue
        return .asymmetric(
            insertion: .opacity.combined(with: .move(edge: forward ? .trailing : .leading)),
            removal: .opacity.combined(with: .move(edge: forward ? .leading : .trailing))
        )
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { item in
                Button {
                    guard item != tab else { return }
                    previousTab = tab
                    SFX.tap()
                    Haptics.selection()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        tab = item
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 20, weight: .semibold))
                        Text(item.title)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundColor(tab == item ? .white : .white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if tab == item {
                            Capsule()
                                .fill(LinearGradient(gradient: Gradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.10)]),
                                                     startPoint: .top, endPoint: .bottom))
                                .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                                .matchedGeometryEffect(id: "tabHighlight", in: ns)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(
            Capsule().stroke(LinearGradient(gradient: Gradient(colors: [.white.opacity(0.4), .white.opacity(0.08)]),
                                            startPoint: .topLeading, endPoint: .bottomTrailing),
                             lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
        .padding(.horizontal, 26)
    }
}
