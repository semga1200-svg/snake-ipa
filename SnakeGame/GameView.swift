import SwiftUI

// Минимальная версия: чёрный экран (полная игра — в истории git, коммит cb09b7b)
struct GameView: View {
    var body: some View {
        Color.black
            .ignoresSafeArea()
    }
}

#Preview {
    GameView()
}
