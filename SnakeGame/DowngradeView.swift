import SwiftUI
import UIKit

// MARK: - Эмуляция отката версии iOS

struct DowngradeScreen: View {
    enum Phase { case select, blobs, download, verify, flash, done }

    struct Version: Identifiable {
        let id = UUID()
        let name: String
        let build: String
        let size: String
    }

    private let versions = [
        Version(name: "iOS 26.1", build: "23B117", size: "12.4 ГБ"),
        Version(name: "iOS 25.4", build: "22H310", size: "11.8 ГБ"),
        Version(name: "iOS 18.5", build: "22F76", size: "8.7 ГБ"),
        Version(name: "iOS 17.4", build: "21E219", size: "7.9 ГБ"),
        Version(name: "iOS 16.7.10", build: "20H232", size: "6.6 ГБ")
    ]

    @State private var phase: Phase = .select
    @State private var selected = 2
    @State private var progress: Double = 0
    @State private var speed: Double = 0
    @State private var apnonce = ""
    @State private var sha = ""
    @State private var flashSeconds = 479
    @State private var task: Task<Void, Never>?
    @State private var appeared = false
    @Namespace private var ns

    var body: some View {
        ZStack {
            VStack(spacing: 14) {
                header
                if phase == .select {
                    selectCard
                    startButton
                } else {
                    progressCard
                    cancelButton
                }
                Spacer()
            }
            .padding(16)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)

            if phase == .flash { flashView }
            if phase == .done { doneView }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { appeared = true }
        }
        .onDisappear {
            task?.cancel()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: Шапка

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.down.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Color(red: 0.45, green: 0.55, blue: 1.0))
            Text("Откат iOS")
                .font(.title2.bold())
                .foregroundColor(.white)
            Spacer()
            EmulationBadge()
        }
    }

    // MARK: Выбор версии

    private var selectCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Выбери версию для «отката»")
                .font(.headline)
                .foregroundColor(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(versions.enumerated()), id: \.element.id) { idx, v in
                        Button {
                            guard phase == .select else { return }
                            SFX.tap()
                            Haptics.selection()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                selected = idx
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text(v.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(v.size)
                                    .font(.caption2)
                                    .opacity(0.65)
                            }
                            .foregroundColor(selected == idx ? .black : .white.opacity(0.75))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background {
                                if selected == idx {
                                    Capsule()
                                        .fill(LinearGradient(gradient: Gradient(colors: [Color(red: 0.55, green: 0.9, blue: 1.0), Color(red: 0.45, green: 0.55, blue: 1.0)]),
                                                             startPoint: .top, endPoint: .bottom))
                                        .matchedGeometryEffect(id: "verSel", in: ns)
                                } else {
                                    Capsule().fill(Color.white.opacity(0.08))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(phase != .select)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }

            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 13))
                Text("SHSH2-блобы найдены в кэше «Thorium»")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
            }

            row(label: "Устройство", value: deviceMachineIdentifier())
            row(label: "Текущая версия", value: "iOS \(UIDevice.current.systemVersion)")
            row(label: "Цель", value: "\(versions[selected].name) (\(versions[selected].build))")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
                .foregroundColor(.white.opacity(0.9))
        }
    }

    private var startButton: some View {
        Button {
            start()
        } label: {
            Label("Начать откат", systemImage: "arrow.down.circle.fill")
        }
        .buttonStyle(GlassButtonStyle(filled: true))
    }

    // MARK: Прогресс

    private var progressCard: some View {
        VStack(spacing: 14) {
            switch phase {
            case .blobs:
                phaseIcon("key.radiowave.forward.fill", color: .cyan, spin: true)
                Text("Ищу SHSH2-блобы…")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("apnonce \(apnonce.isEmpty ? "…" : apnonce)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                GlassProgress(value: 0.35)
            case .download:
                Text("Скачиваю \(versions[selected].name)")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("IPSFW · \(versions[selected].size)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                GlassProgress(value: progress)
                HStack {
                    Text(String(format: "%.0f МБ/с", speed))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.cyan)
                    Spacer()
                    Text(String(format: "%.0f%%", progress * 100))
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundColor(.white.opacity(0.8))
                }
            case .verify:
                phaseIcon("checkmark.seal.fill", color: .green, spin: false)
                Text("Проверяю подпись Apple…")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("sha256 \(sha.isEmpty ? "…" : String(sha.prefix(24)))…")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                GlassProgress(value: 0.85)
            case .flash:
                Text("Прошивка…")
                    .font(.headline)
                    .foregroundColor(.white)
            case .select, .done:
                EmptyView()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .glassCard()
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: phase)
    }

    private func phaseIcon(_ name: String, color: Color, spin: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 40))
            .foregroundColor(color)
            .shadow(color: color.opacity(0.7), radius: 10)
            .modifier(SpinIfNeeded(enabled: spin))
    }

    private var cancelButton: some View {
        Button {
            SFX.click()
            task?.cancel()
            UIApplication.shared.isIdleTimerDisabled = false
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                phase = .select
            }
        } label: {
            Label("Отмена", systemImage: "xmark")
        }
        .buttonStyle(GlassButtonStyle(tint: .red))
    }

    // MARK: Экран прошивки

    private var flashView: some View {
        VStack(spacing: 22) {
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.system(size: 72, weight: .light))
                .foregroundColor(.white.opacity(0.9))
            Text("Обновление ПО iPhone…")
                .font(.headline)
                .foregroundColor(.white)
            Text("Осталось примерно \(flashSeconds / 60):\(String(format: "%02d", flashSeconds % 60))")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
            GlassProgress(value: 1 - Double(flashSeconds) / 600)
                .frame(width: 220)
            Text("Не отключайте устройство")
                .font(.caption)
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .transition(.opacity)
    }

    // MARK: Готово

    private var doneView: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 62))
                    .foregroundColor(.green)
                    .shadow(color: .green.opacity(0.8), radius: 14)
                Text("\(versions[selected].name) установлена")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                Text("Сборка \(versions[selected].build) · это симуляция")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.6))
                Button {
                    SFX.click()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        phase = .select
                    }
                } label: {
                    Text("Готово")
                }
                .buttonStyle(GlassButtonStyle(filled: true))
            }
            .padding(30)
            .glassCard()
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
    }

    // MARK: Логика

    private func start() {
        SFX.click()
        progress = 0
        speed = 0
        apnonce = randomHex(40)
        sha = randomHex(64)
        phase = .blobs
        SFX.whoosh()
        UIApplication.shared.isIdleTimerDisabled = true

        task = Task { @MainActor in
            do {
                // 1. Блобы
                try await Task.sleep(nanoseconds: 1_200_000_000)
                SFX.pop()
                try await Task.sleep(nanoseconds: 800_000_000)

                // 2. Скачивание
                phase = .download
                SFX.whoosh()
                let steps = 36
                for i in 1...steps {
                    try await Task.sleep(nanoseconds: 110_000_000)
                    progress = Double(i) / Double(steps)
                    speed = 90 + Double.random(in: 0...70)
                    if i == steps / 4 || i == steps / 2 || i == steps * 3 / 4 { SFX.tick() }
                }

                // 3. Проверка подписи
                phase = .verify
                try await Task.sleep(nanoseconds: 900_000_000)
                SFX.pop()
                try await Task.sleep(nanoseconds: 1_000_000_000)

                // 4. Прошивка
                phase = .flash
                SFX.boot()
                flashSeconds = Int.random(in: 320...580)
                let flashes = 28
                let base = flashSeconds
                for _ in 1...flashes {
                    try await Task.sleep(nanoseconds: 150_000_000)
                    flashSeconds = max(1, flashSeconds - base / flashes - Int.random(in: 0...4))
                    SFX.tick()
                }
                try await Task.sleep(nanoseconds: 500_000_000)

                phase = .done
                SFX.chime()
                UIApplication.shared.isIdleTimerDisabled = false
            } catch {
                phase = .select
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }
}

// MARK: - Вращение спиннера

struct SpinIfNeeded: ViewModifier {
    var enabled: Bool
    @State private var angle: Double = 0

    func body(content: Content) -> some View {
        if enabled {
            content
                .rotationEffect(.degrees(angle))
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        angle = 360
                    }
                }
        } else {
            content
        }
    }
}
