import SwiftUI
import UIKit
import Network
import Darwin

struct InfoView: View {
    @State private var localIPs: [String] = []
    @State private var publicIP: String = "—"
    @State private var isFetchingPublicIP = false
    @State private var pathStatus: String = "…"
    @State private var pathType: String = "…"
    @State private var batteryLevel: Float = -1
    @State private var batteryState: UIDevice.BatteryState = .unknown
    @State private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var appeared = false
    @State private var monitor: NWPathMonitor?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                deviceCard
                systemCard
                storageCard
                networkCard
                actionCard
            }
            .padding(16)
            .padding(.bottom, 110)
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { appeared = true }
            startMonitoring()
            refresh()
        }
        .onDisappear { stopMonitoring() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Об устройстве")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text("Реальные данные системы")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            Button { SFX.tap(); refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
        }
    }

    private var deviceCard: some View {
        infoCard(title: "Устройство", icon: "iphone") {
            row("Имя", UIDevice.current.name)
            row("Модель", deviceModelName())
            row("Идентификатор", deviceMachineIdentifier())
            row("Система", "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
            if let id = UIDevice.current.identifierForVendor?.uuidString {
                row("ID устройства", String(id.prefix(18)) + "…")
            }
        }
    }

    private var systemCard: some View {
        infoCard(title: "Система", icon: "cpu") {
            let mem = ProcessInfo.processInfo.physicalMemory
            row("ОЗУ (всего)", ByteCountFormatter.string(fromByteCount: Int64(mem), countStyle: .memory))
            row("Ядра CPU", "\(ProcessInfo.processInfo.processorCount) (активно \(ProcessInfo.processInfo.activeProcessorCount))")
            row("Аптайм", formatUptime(ProcessInfo.processInfo.systemUptime))
            row("Экономия энергии", lowPowerMode ? "Включена" : "Выключена")
            row("Термосостояние", thermalString(ProcessInfo.processInfo.thermalState))
            let b = UIScreen.main.bounds
            let s = UIScreen.main.scale
            row("Экран", "\(Int(b.width))×\(Int(b.height)) pt @\(Int(s))x")
        }
    }

    private var storageCard: some View {
        infoCard(title: "Память и батарея", icon: "internaldrive") {
            let (total, free) = diskSpace()
            if total > 0 {
                let used = total - free
                row("Диск всего", ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
                row("Свободно", ByteCountFormatter.string(fromByteCount: free, countStyle: .file))
                row("Занято", ByteCountFormatter.string(fromByteCount: used, countStyle: .file))
                let pct = Double(used) / Double(total)
                GlassProgress(value: pct)
                    .padding(.top, 4)
                Text("Использовано \(Int(pct * 100))%")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            } else {
                row("Диск", "Нет данных")
            }
            Divider().background(Color.white.opacity(0.15)).padding(.vertical, 4)
            if batteryLevel >= 0 {
                row("Батарея", "\(Int(batteryLevel * 100))%")
                row("Состояние", batteryStateString(batteryState))
                GlassProgress(value: Double(batteryLevel))
                    .padding(.top, 4)
            } else {
                row("Батарея", "Недоступно")
            }
        }
    }

    private var networkCard: some View {
        infoCard(title: "Сеть", icon: "wifi") {
            row("Статус", pathStatus)
            row("Интерфейс", pathType)
            if localIPs.isEmpty {
                row("Локальный IP", "—")
            } else {
                ForEach(localIPs, id: \.self) { ip in
                    row("Локальный IP", ip)
                }
            }
            HStack {
                Text("Публичный IP")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                if isFetchingPublicIP {
                    ProgressView().tint(.white)
                } else {
                    Text(publicIP)
                        .font(.system(.footnote, design: .monospaced).weight(.semibold))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            Button {
                SFX.tap()
                fetchPublicIP()
            } label: {
                Label("Узнать публичный IP", systemImage: "globe")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(GlassButtonStyle())
            .padding(.top, 4)
        }
    }

    private var actionCard: some View {
        infoCard(title: "Действия", icon: "square.and.arrow.up") {
            ShareReportButton()
        }
    }

    // MARK: - UI helpers

    private func infoCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.cyan)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.55))
            Spacer()
            Text(value)
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
                .foregroundColor(.white.opacity(0.92))
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Data

    private func refresh() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = UIDevice.current.batteryLevel
        batteryState = UIDevice.current.batteryState
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        localIPs = Self.getLocalIPAddresses()
    }

    private func startMonitoring() {
        let m = NWPathMonitor()
        monitor = m
        m.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                self.pathStatus = path.status == .satisfied ? "Подключено" : (path.status == .unsatisfied ? "Нет сети" : "Требуется подключение")
                var types: [String] = []
                if path.usesInterfaceType(.wifi) { types.append("Wi‑Fi") }
                if path.usesInterfaceType(.cellular) { types.append("Сотовая") }
                if path.usesInterfaceType(.wiredEthernet) { types.append("Ethernet") }
                if path.usesInterfaceType(.loopback) { types.append("Loopback") }
                self.pathType = types.isEmpty ? "—" : types.joined(separator: ", ")
            }
        }
        m.start(queue: DispatchQueue(label: "net.monitor"))
    }

    private func stopMonitoring() {
        monitor?.cancel()
        monitor = nil
    }

    private func fetchPublicIP() {
        guard let url = URL(string: "https://api.ipify.org") else { return }
        isFetchingPublicIP = true
        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                if let data = data, let s = String(data: data, encoding: .utf8) {
                    self.publicIP = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    SFX.success()
                } else {
                    self.publicIP = "Не удалось получить"
                    SFX.error()
                }
                self.isFetchingPublicIP = false
            }
        }.resume()
    }

    private func diskSpace() -> (Int64, Int64) {
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let total = attrs[.systemSize] as? NSNumber,
           let free = attrs[.systemFreeSize] as? NSNumber {
            return (total.int64Value, free.int64Value)
        }
        return (0, 0)
    }

    private func formatUptime(_ t: TimeInterval) -> String {
        let s = Int(t)
        let d = s / 86400
        let h = (s % 86400) / 3600
        let m = (s % 3600) / 60
        if d > 0 { return "\(d)д \(h)ч \(m)м" }
        if h > 0 { return "\(h)ч \(m)м" }
        return "\(m)м"
    }

    private func batteryStateString(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .charging: return "Заряжается"
        case .full: return "Полностью заряжена"
        case .unplugged: return "Не заряжается"
        default: return "Неизвестно"
        }
    }

    private func thermalString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Норма"
        case .fair: return "Повышенная"
        case .serious: return "Высокая"
        case .critical: return "Критическая"
        @unknown default: return "—"
        }
    }

    private func deviceModelName() -> String {
        let id = deviceMachineIdentifier()
        // Простая карта частых моделей; если нет — показываем идентификатор
        let map: [String: String] = [
            "iPhone10,1": "iPhone 8", "iPhone10,4": "iPhone 8",
            "iPhone10,2": "iPhone 8 Plus", "iPhone10,5": "iPhone 8 Plus",
            "iPhone10,3": "iPhone X", "iPhone10,6": "iPhone X",
            "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max", "iPhone11,6": "iPhone XS Max",
            "iPhone11,8": "iPhone XR",
            "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max",
            "iPhone12,8": "iPhone SE (2)",
            "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
            "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
            "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,6": "iPhone SE (3)",
            "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
            "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus",
            "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,5": "iPhone 16e",
            "i386": "Simulator", "x86_64": "Simulator", "arm64": "Simulator"
        ]
        return map[id] ?? UIDevice.current.model
    }

    static func getLocalIPAddresses() -> [String] {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name.hasPrefix("pdp_ip") || name.hasPrefix("utun") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    let address = String(cString: hostname)
                    if !address.isEmpty && address != "0.0.0.0" && !address.hasPrefix("fe80") {
                        let label = name == "en0" ? "Wi‑Fi" : (name.hasPrefix("pdp_ip") ? "Cell" : name)
                        addresses.append("\(address) (\(label))")
                    }
                }
            }
        }
        // уникальные
        var seen = Set<String>()
        return addresses.filter { seen.insert($0).inserted }
    }
}

// Кнопка «поделиться отчётом» (вынесена, чтобы использовать ShareSheet)
struct ShareReportButton: View {
    @State private var showShare = false
    @State private var reportText = ""

    var body: some View {
        Button {
            SFX.tap()
            reportText = buildReport()
            showShare = true
        } label: {
            Label("Поделиться отчётом", systemImage: "square.and.arrow.up")
                .font(.footnote.weight(.semibold))
        }
        .buttonStyle(GlassButtonStyle())
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [reportText])
        }
    }

    private func buildReport() -> String {
        let (total, free) = {
            if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
               let t = attrs[.systemSize] as? NSNumber,
               let f = attrs[.systemFreeSize] as? NSNumber { return (t.int64Value, f.int64Value) }
            return (Int64(0), Int64(0))
        }()
        let mem = ProcessInfo.processInfo.physicalMemory
        UIDevice.current.isBatteryMonitoringEnabled = true
        let bl = UIDevice.current.batteryLevel
        return """
        Отчёт об устройстве
        ————————————————
        Имя: \(UIDevice.current.name)
        Модель: \(deviceMachineIdentifier())
        Система: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        Экран: \(Int(UIScreen.main.bounds.width))×\(Int(UIScreen.main.bounds.height)) @\(Int(UIScreen.main.scale))x
        ОЗУ: \(ByteCountFormatter.string(fromByteCount: Int64(mem), countStyle: .memory))
        CPU ядер: \(ProcessInfo.processInfo.processorCount)
        Диск: всего \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)), свободно \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file))
        Батарея: \(bl >= 0 ? "\(Int(bl*100))%" : "н/д")
        Аптайм: \(Int(ProcessInfo.processInfo.systemUptime / 3600)) ч
        """
    }
}