import SwiftUI
import UIKit

// MARK: - Эмуляция джейлбрейка

struct JailbreakScreen: View {
    enum Phase { case idle, running, done, cancelled }
    enum LogKind { case normal, ok, info, warn, accent }

    struct LogLine: Identifiable {
        let id = UUID()
        let text: String
        let kind: LogKind
    }

    @State private var phase: Phase = .idle
    @State private var lines: [LogLine] = []
    @State private var progress: Double = 0
    @State private var task: Task<Void, Error>?
    @State private var ecid = ""
    @State private var deviceLine = ""
    @State private var appeared = false
    @State private var cursorOn = false

    var body: some View {
        VStack(spacing: 14) {
            header
            deviceCard
            console
            controls
        }
        .padding(16)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { appeared = true }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { cursorOn = true }
            if ecid.isEmpty {
                ecid = "0x" + randomHex(12)
                deviceLine = "\(deviceMachineIdentifier()) · iOS \(UIDevice.current.systemVersion)"
            }
        }
        .onDisappear {
            task?.cancel()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: Шапка

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.green)
                Text("LiquidJB")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Spacer()
                EmulationBadge()
            }
            HStack {
                Text("Полусвободный джейлбрейк для iOS 15–26")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }
        }
    }

    // MARK: Информация об устройстве

    private var deviceCard: some View {
        VStack(spacing: 8) {
            row(icon: "iphone.gen3", label: deviceLine.isEmpty ? "устройство…" : deviceLine)
            row(icon: "number", label: "ECID \(ecid.isEmpty ? "…" : ecid)")
            row(icon: "internaldrive", label: freeDisk())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18)
    }

    private func row(icon: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.cyan)
                .frame(width: 18)
            Text(label)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
        }
    }

    private func freeDisk() -> String {
        if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let cap = values.volumeAvailableCapacity {
            return String(format: "%.1f ГБ свободно на диске", Double(cap) / 1_000_000_000)
        }
        return "диск: нет данных"
    }

    // MARK: Консоль

    private var console: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(lines) { line in
                            Text(line.text)
                                .font(.system(.footnote, design: .monospaced).weight(line.kind == .accent ? .semibold : .regular))
                                .foregroundColor(color(line.kind))
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .id(line.id)
                        }
                        if phase == .running {
                            Text("▊")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundColor(.green)
                                .opacity(cursorOn ? 1 : 0)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
                .onChange(of: lines.count) { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lines.last?.id, anchor: .bottom)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.5)))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )

            if phase == .done {
                doneOverlay
            }
            if phase == .cancelled {
                cancelledOverlay
            }
        }
    }

    private var doneOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 62))
                .foregroundColor(.green)
                .shadow(color: .green.opacity(0.8), radius: 14)
            Text("Готово!")
                .font(.title2.bold())
                .foregroundColor(.white)
            Text("Устройство «взломано». Это симуляция 🙂")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(24)
        .glassCard()
        .transition(.scale(scale: 0.7).combined(with: .opacity))
    }

    private var cancelledOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.red)
            Text("Прервано пользователем")
                .font(.headline)
                .foregroundColor(.white)
            Text("Устройство в исходном состоянии")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(24)
        .glassCard()
        .transition(.scale(scale: 0.7).combined(with: .opacity))
    }

    private func color(_ kind: LogKind) -> Color {
        switch kind {
        case .normal: return .white.opacity(0.85)
        case .ok: return Color(red: 0.4, green: 0.95, blue: 0.55)
        case .info: return .cyan
        case .warn: return .yellow
        case .accent: return .white
        }
    }

    // MARK: Кнопки

    private var controls: some View {
        HStack(spacing: 12) {
            switch phase {
            case .idle, .cancelled:
                Button {
                    run()
                } label: {
                    Label("Джейлбрейк", systemImage: "bolt.fill")
                }
                .buttonStyle(GlassButtonStyle(filled: true))
                Spacer()
            case .running:
                Button {
                    stop()
                } label: {
                    Label("Прервать", systemImage: "stop.fill")
                }
                .buttonStyle(GlassButtonStyle(tint: .red))
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Эксплойт выполняется…")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    GlassProgress(value: progress)
                        .frame(width: 110)
                }
            case .done:
                Button {
                    run()
                } label: {
                    Label("Ещё раз", systemImage: "arrow.clockwise")
                }
                .buttonStyle(GlassButtonStyle())
                Spacer()
                Button {
                    SFX.click()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        phase = .idle
                        lines = []
                        progress = 0
                    }
                } label: {
                    Text("Сброс")
                }
                .buttonStyle(GlassButtonStyle(filled: true))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: phase)
    }

    // MARK: Сценарий

    private var script: [(text: String, kind: LogKind, delay: Double, sound: String?)] {
        [
            ("поиск уязвимого вектора…", .normal, 0.5, nil),
            ("эксплойт kernel_panic_v2: загружен", .info, 0.9, "tap"),
            ("tfp0: получен ✔", .ok, 0.7, "pop"),
            ("снятие AMFI-ограничений…", .normal, 0.8, nil),
            ("AMFI: отключен ✔", .ok, 0.6, "pop"),
            ("remount / → read-write… OK", .ok, 0.7, nil),
            ("закачка bootstrap (24.1 МБ)…", .normal, 0.5, "whoosh"),
            ("bootstrap: распакован ✔", .ok, 1.1, nil),
            ("установка Sileo…", .normal, 0.7, nil),
            ("Sileo: установлен ✔", .ok, 0.9, "pop"),
            ("инъекция твиков в SpringBoard…", .normal, 0.6, nil),
            ("killall SpringBoard…", .warn, 1.0, "tap"),
            ("respring: OK", .ok, 0.8, nil),
            ("устройство взломано 🐦", .accent, 0.6, nil)
        ]
    }

    private func run() {
        task?.cancel()
        lines = []
        progress = 0
        phase = .running
        SFX.boot()
        UIApplication.shared.isIdleTimerDisabled = true

        task = Task { @MainActor in
            do {
                let total = Double(script.count)
                for (i, step) in script.enumerated() {
                    try await Task.sleep(nanoseconds: UInt64(step.delay * 1_000_000_000))
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        lines.append(LogLine(text: "→ " + step.text, kind: step.kind))
                        progress = Double(i + 1) / total
                    }
                    SFX.tick()
                    if let s = step.sound { SoundManager.shared.play(s) }
                    Haptics.light()
                }
                phase = .done
                SFX.chime()
                UIApplication.shared.isIdleTimerDisabled = false
            } catch {
                phase = .cancelled
                SFX.error()
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    private func stop() {
        task?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
