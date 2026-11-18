import SwiftUI

struct SimulationHubView: View {
    @State private var mode = 0
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 6) {
                HStack {
                    Text("Симуляции")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Text("Развлекательные экраны — ничего реально не меняют на устройстве")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)

                Picker("", selection: $mode) {
                    Text("Джейлбрейк").tag(0)
                    Text("Откат iOS").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .onChange(of: mode) { _ in SFX.tap(); Haptics.selection() }
            }

            Group {
                if mode == 0 {
                    JailbreakScreen()
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                } else {
                    DowngradeScreen()
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: mode)
        }
        .padding(.bottom, 110)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { appeared = true }
        }
    }
}