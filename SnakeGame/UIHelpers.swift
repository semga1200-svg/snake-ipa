import SwiftUI
import UIKit

// MARK: - Живой градиентный фон (liquid glass ambient)

struct GlassBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.03, blue: 0.07).ignoresSafeArea()
            GeometryReader { geo in
                ZStack {
                    blob(Color(red: 0.10, green: 0.45, blue: 1.0), size: geo.size.width * 0.9)
                        .offset(x: -geo.size.width * 0.25, y: -geo.size.height * 0.22)
                    blob(Color(red: 0.62, green: 0.20, blue: 1.0), size: geo.size.width)
                        .offset(x: geo.size.width * 0.30, y: 0)
                    blob(Color(red: 0.0, green: 0.80, blue: 0.70), size: geo.size.width * 0.85)
                        .offset(x: -geo.size.width * 0.05, y: geo.size.height * 0.35)
                }
                .blur(radius: 100)
                .opacity(0.55)
                .scaleEffect(animate ? 1.18 : 1.0)
                .rotationEffect(.degrees(animate ? 8 : -4))
                .animation(.easeInOut(duration: 9).repeatForever(autoreverses: true), value: animate)
                .onAppear { animate = true }
            }
            .ignoresSafeArea()
        }
    }

    private func blob(_ color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(gradient: Gradient(colors: [color.opacity(0.9), color.opacity(0.0)]),
                                 center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
    }
}

// MARK: - Стеклянная карточка

extension View {
    func glassCard(cornerRadius: CGFloat = 24) -> some View {
        self
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(LinearGradient(gradient: Gradient(colors: [.white.opacity(0.35), .white.opacity(0.05)]),
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}

// MARK: - Стеклянная кнопка с press-эффектом

struct GlassButtonStyle: ButtonStyle {
    var tint: Color = .white
    var filled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(filled ? .black : tint)
            .padding(.horizontal, 28)
            .padding(.vertical, 13)
            .background(
                Capsule().fill(filled
                    ? AnyShapeStyle(LinearGradient(gradient: Gradient(colors: [Color(red: 0.45, green: 0.95, blue: 0.55), Color(red: 0.15, green: 0.75, blue: 0.45)]), startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(Material.ultraThin))
            )
            .overlay(
                Capsule().stroke(LinearGradient(gradient: Gradient(colors: [.white.opacity(0.45), .white.opacity(0.08)]),
                                                startPoint: .topLeading, endPoint: .bottomTrailing),
                                 lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
            .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
    }
}

// MARK: - Эффект тряски (game over)

struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let travel: CGFloat = 11
        let shakes: CGFloat = 3
        return ProjectionTransform(
            CGAffineTransform(translationX: travel * sin(animatableData * .pi * shakes * 2), y: 0))
    }
}

// MARK: - Бейдж «симуляция»

struct EmulationBadge: View {
    var body: some View {
        Text("СИМУЛЯЦИЯ · НИЧЕГО НЕ МЕНЯЕТСЯ")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white.opacity(0.55))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

// MARK: - Стеклянный прогресс-бар

struct GlassProgress: View {
    var value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(gradient: Gradient(colors: [Color(red: 0.35, green: 0.85, blue: 1.0), Color(red: 0.45, green: 0.5, blue: 1.0)]),
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(10, geo.size.width * CGFloat(min(1, max(0, value)))))
                    .animation(.linear(duration: 0.12), value: value)
            }
        }
        .frame(height: 10)
    }
}

// MARK: - Плашка с данными устройства

func deviceMachineIdentifier() -> String {
    var info = utsname()
    uname(&info)
    return withUnsafeBytes(of: info.machine) { ptr -> String in
        String(cString: ptr.baseAddress!.assumingMemoryBound(to: CChar.self))
    }
}

func randomHex(_ count: Int) -> String {
    (0..<count).map { _ in "0123456789ABCDEF".randomElement()! }.joined()
}
