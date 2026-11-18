import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

struct ToolsView: View {
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                PasswordGeneratorCard()
                QRGeneratorCard()
                ClipboardCard()
                QuickActionsCard()
            }
            .padding(16)
            .padding(.bottom, 110)
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { appeared = true }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Инструменты")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text("Полезные утилиты на каждый день")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
        }
    }
}

// MARK: - Генератор паролей

struct PasswordGeneratorCard: View {
    @State private var length: Double = 16
    @State private var useUpper = true
    @State private var useDigits = true
    @State private var useSymbols = true
    @State private var password = ""
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleRow(icon: "key.fill", title: "Генератор паролей")

            if !password.isEmpty {
                Text(password)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundColor(.white)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.35)))
                    .contextMenu {
                        Button { copyPassword() } label: { Label("Копировать", systemImage: "doc.on.doc") }
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Длина: \(Int(length))")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                }
                Slider(value: $length, in: 6...32, step: 1)
                    .tint(.cyan)
            }

            HStack(spacing: 12) {
                ToggleChip("A-Z", isOn: $useUpper)
                ToggleChip("0-9", isOn: $useDigits)
                ToggleChip("#$%", isOn: $useSymbols)
            }

            HStack(spacing: 10) {
                Button { generate() } label: {
                    Label("Сгенерировать", systemImage: "wand.and.stars")
                }
                .buttonStyle(GlassButtonStyle(filled: true))

                if !password.isEmpty {
                    Button { copyPassword() } label: {
                        Label(copied ? "Скопировано" : "Копировать", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20)
        .onAppear { if password.isEmpty { generate() } }
    }

    private func generate() {
        var chars = Array("abcdefghijklmnopqrstuvwxyz")
        if useUpper { chars += Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ") }
        if useDigits { chars += Array("0123456789") }
        if useSymbols { chars += Array("!@#$%^&*()-_=+[]{}?/") }
        var result = ""
        for _ in 0..<Int(length) {
            if let c = chars.randomElement() { result.append(c) }
        }
        password = result
        copied = false
        SFX.pop()
    }

    private func copyPassword() {
        UIPasteboard.general.string = password
        copied = true
        SFX.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}

struct ToggleChip: View {
    let title: String
    @Binding var isOn: Bool
    init(_ title: String, isOn: Binding<Bool>) { self.title = title; self._isOn = isOn }
    var body: some View {
        Button {
            SFX.tap(); isOn.toggle()
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundColor(isOn ? .black : .white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(isOn ? Color.cyan : Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - QR генератор

struct QRGeneratorCard: View {
    @State private var text = ""
    @State private var qrImage: UIImage?
    @State private var showShare = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleRow(icon: "qrcode", title: "QR-код")

            TextField("Текст или ссылка", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.3)))
                .foregroundColor(.white)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))

            HStack(spacing: 10) {
                Button { generate() } label: {
                    Label("Создать", systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(GlassButtonStyle(filled: true))
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)

                if qrImage != nil {
                    Button { showShare = true; SFX.tap() } label: {
                        Label("Поделиться", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }

            if let img = qrImage {
                HStack {
                    Spacer()
                    Image(uiImage: img)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                    Spacer()
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20)
        .sheet(isPresented: $showShare) {
            if let img = qrImage { ShareSheet(items: [img]) }
        }
    }

    private func generate() {
        let str = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return }
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(str.utf8)
        filter.correctionLevel = "M"
        if let output = filter.outputImage {
            let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
            if let cg = context.createCGImage(scaled, from: scaled.extent) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    qrImage = UIImage(cgImage: cg)
                }
                SFX.success()
                return
            }
        }
        SFX.error()
    }
}

// MARK: - Буфер обмена

struct ClipboardCard: View {
    @State private var clipText: String = ""
    @State private var customText: String = ""
    @State private var status: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleRow(icon: "doc.on.clipboard", title: "Буфер обмена")

            if clipText.isEmpty {
                Text("Буфер пуст или недоступен")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.5))
            } else {
                Text(clipText)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(4)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.3)))
            }

            HStack(spacing: 10) {
                Button { readClipboard() } label: {
                    Label("Прочитать", systemImage: "arrow.clockwise")
                }
                .buttonStyle(GlassButtonStyle())

                Button { clearClipboard() } label: {
                    Label("Очистить", systemImage: "trash")
                }
                .buttonStyle(GlassButtonStyle(tint: .red))
            }

            Divider().background(Color.white.opacity(0.15))

            TextField("Текст для копирования", text: $customText)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.3)))
                .foregroundColor(.white)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))

            Button { copyCustom() } label: {
                Label(status.isEmpty ? "Скопировать в буфер" : status, systemImage: status.isEmpty ? "doc.on.doc" : "checkmark")
            }
            .buttonStyle(GlassButtonStyle(filled: true))
            .disabled(customText.isEmpty)
            .opacity(customText.isEmpty ? 0.5 : 1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20)
        .onAppear { readClipboard() }
    }

    private func readClipboard() {
        clipText = UIPasteboard.general.string ?? ""
        SFX.tick()
    }

    private func clearClipboard() {
        UIPasteboard.general.string = ""
        clipText = ""
        SFX.tap()
    }

    private func copyCustom() {
        UIPasteboard.general.string = customText
        status = "Скопировано"
        SFX.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { status = "" }
    }
}

// MARK: - Быстрые действия

struct QuickActionsCard: View {
    @State private var shareSheet = false
    @State private var infoText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleRow(icon: "bolt.fill", title: "Быстрые действия")

            Button { testFeedback() } label: {
                HStack {
                    Label("Тест звука и вибрации", systemImage: "speaker.wave.2.fill")
                    Spacer()
                    Image(systemName: "play.circle")
                }
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)

            Button { openSettings() } label: {
                HStack {
                    Label("Открыть настройки iOS", systemImage: "gearshape.fill")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)

            Button { copyTimestamp() } label: {
                HStack {
                    Label("Скопировать текущие дату/время", systemImage: "clock")
                    Spacer()
                    Image(systemName: "doc.on.doc")
                }
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20)
    }

    private func testFeedback() {
        SFX.click()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { SFX.pop() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { SFX.success() }
        Haptics.medium()
    }

    private func openSettings() {
        SFX.tap()
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func copyTimestamp() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "dd.MM.yyyy HH:mm:ss (ZZZZ)"
        UIPasteboard.general.string = f.string(from: Date())
        SFX.success()
    }
}

// MARK: - Shared helpers

private func titleRow(icon: String, title: String) -> some View {
    HStack(spacing: 8) {
        Image(systemName: icon).foregroundColor(.cyan)
        Text(title).font(.headline).foregroundColor(.white)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}