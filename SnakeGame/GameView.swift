import SwiftUI

// MARK: - Модель

struct Cell: Equatable {
    var x: Int
    var y: Int
}

enum Direction {
    case up, down, left, right

    var delta: Cell {
        switch self {
        case .up:    return Cell(x: 0, y: -1)
        case .down:  return Cell(x: 0, y: 1)
        case .left:  return Cell(x: -1, y: 0)
        case .right: return Cell(x: 1, y: 0)
        }
    }

    func isOpposite(to other: Direction) -> Bool {
        switch (self, other) {
        case (.up, .down), (.down, .up), (.left, .right), (.right, .left):
            return true
        default:
            return false
        }
    }
}

final class GameModel: ObservableObject {
    static let cols = 19
    static let rows = 26

    @Published var snake: [Cell] = []
    @Published var prevSnake: [Cell] = []
    @Published var food = Cell(x: 5, y: 5)
    @Published var direction: Direction = .right
    @Published var isRunning = false
    @Published var isGameOver = false
    @Published var isPaused = false
    @Published var score = 0
    @Published var best = UserDefaults.standard.integer(forKey: "bestScore")
    @Published var lastTickAt = Date()

    private var pendingDirection: Direction = .right
    private var timer: Timer?

    var tickInterval: Double {
        max(0.07, 0.16 - Double(score) * 0.003)
    }

    init() { reset() }
    deinit { timer?.invalidate() }

    func reset() {
        snake = [Cell(x: 9, y: 13), Cell(x: 8, y: 13), Cell(x: 7, y: 13)]
        prevSnake = snake
        direction = .right
        pendingDirection = .right
        score = 0
        isGameOver = false
        isPaused = false
        spawnFood()
    }

    func start() {
        reset()
        isRunning = true
        lastTickAt = Date()
        scheduleTimer()
    }

    func pause() {
        guard isRunning else { return }
        isRunning = false
        isPaused = true
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        isRunning = true
        scheduleTimer()
    }

    func turn(_ newDirection: Direction) {
        guard isRunning, !isPaused else { return }
        if newDirection.isOpposite(to: pendingDirection) { return }
        pendingDirection = newDirection
    }

    func tick() {
        guard isRunning, !isGameOver, let head = snake.first else { return }
        direction = pendingDirection
        let next = Cell(x: head.x + direction.delta.x, y: head.y + direction.delta.y)

        let hitsWall = next.x < 0 || next.x >= Self.cols || next.y < 0 || next.y >= Self.rows
        let hitsSelf = snake.dropLast().contains(next)
        if hitsWall || hitsSelf {
            gameOver()
            return
        }

        let old = snake
        snake.insert(next, at: 0)
        if next == food {
            score += 1
            if score > best {
                best = score
                UserDefaults.standard.set(best, forKey: "bestScore")
            }
            spawnFood()
            scheduleTimer()
        } else {
            snake.removeLast()
        }
        prevSnake = old
        lastTickAt = Date()
    }

    /// 0..1 — доля пройденного пути между тиками (для плавной отрисовки)
    func motionProgress(at date: Date) -> Double {
        guard isRunning, !isGameOver else { return 1 }
        return min(1, date.timeIntervalSince(lastTickAt) / tickInterval)
    }

    private func gameOver() {
        isRunning = false
        isGameOver = true
        prevSnake = snake
        lastTickAt = Date.distantPast
        timer?.invalidate()
        timer = nil
    }

    private func spawnFood() {
        if snake.count >= Self.cols * Self.rows {
            gameOver()
            return
        }
        var candidate: Cell
        repeat {
            candidate = Cell(x: Int.random(in: 0..<Self.cols),
                             y: Int.random(in: 0..<Self.rows))
        } while snake.contains(candidate)
        food = candidate
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}

// MARK: - Экран игры

struct SnakeScreen: View {
    @StateObject private var game = GameModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var bump = false
    @State private var shake: CGFloat = 0
    @State private var pulse = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 14) {
            header
            board
            Text("Свайп по полю — поворот змейки")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.45))
        }
        .padding(16)
        .scaleEffect(appeared ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { appeared = true }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { game.pause() }
        }
        .onChange(of: game.score) { _ in
            SFX.pop()
            bump = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { bump = false }
            }
        }
        .onChange(of: game.isGameOver) { over in
            guard over else { return }
            SFX.error()
            withAnimation(.easeOut(duration: 0.5)) { shake = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { shake = 0 }
        }
    }

    // MARK: Шапка

    private var header: some View {
        HStack(spacing: 12) {
            chip(title: "СЧЁТ", value: "\(game.score)", isBumping: bump)
            Spacer()
            Button {
                SFX.click()
                if game.isRunning {
                    game.pause()
                } else if game.isPaused {
                    game.resume()
                }
            } label: {
                Image(systemName: game.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
            }
            .background(Circle().fill(.ultraThinMaterial))
            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
            Spacer()
            chip(title: "РЕКОРД", value: "\(game.best)", isBumping: false)
        }
    }

    private func chip(title: String, value: String, isBumping: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            Text(value)
                .font(.title2.bold())
                .foregroundColor(.white)
                .scaleEffect(isBumping ? 1.25 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: isBumping)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minWidth: 86, alignment: .leading)
        .glassCard(cornerRadius: 18)
    }

    // MARK: Поле

    private var board: some View {
        GeometryReader { geo in
            let cellSize = min((geo.size.width - 6) / CGFloat(GameModel.cols),
                               (geo.size.height - 6) / CGFloat(GameModel.rows))
            let w = cellSize * CGFloat(GameModel.cols)
            let h = cellSize * CGFloat(GameModel.rows)
            ZStack {
                TimelineView(.animation) { timeline in
                    Canvas { ctx, _ in
                        draw(in: &ctx, cell: cellSize, date: timeline.date)
                    }
                }
                .frame(width: w, height: h)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.4)))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(LinearGradient(gradient: Gradient(colors: [.white.opacity(0.28), .white.opacity(0.05)]),
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1)
                )
                .modifier(ShakeEffect(animatableData: shake))

                if game.isRunning || game.isPaused {
                    Circle()
                        .stroke(Color.white.opacity(pulse ? 0.15 : 0.6), lineWidth: 1.5)
                        .frame(width: cellSize * 0.85, height: cellSize * 0.85)
                        .scaleEffect(pulse ? 1.35 : 0.9)
                        .position(x: CGFloat(game.food.x) * cellSize + cellSize / 2,
                                  y: CGFloat(game.food.y) * cellSize + cellSize / 2)
                }

                if !game.isRunning {
                    overlay
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: game.isRunning)
        }
        .gesture(
            DragGesture(minimumDistance: 14)
                .onEnded { value in
                    let t = value.translation
                    SFX.tick()
                    Haptics.selection()
                    if abs(t.width) > abs(t.height) {
                        game.turn(t.width > 0 ? .right : .left)
                    } else {
                        game.turn(t.height > 0 ? .down : .up)
                    }
                }
        )
    }

    // MARK: Отрисовка (с интерполяцией между тиками)

    private func draw(in ctx: inout GraphicsContext, cell: CGFloat, date: Date) {
        let t = CGFloat(game.motionProgress(at: date))

        for x in 0..<GameModel.cols {
            for y in 0..<GameModel.rows {
                let px = CGFloat(x) * cell + cell / 2
                let py = CGFloat(y) * cell + cell / 2
                ctx.fill(Path(ellipseIn: CGRect(x: px - 1, y: py - 1, width: 2, height: 2)),
                         with: .color(.white.opacity(0.05)))
            }
        }

        let fr = CGRect(x: CGFloat(game.food.x) * cell + cell * 0.16,
                        y: CGFloat(game.food.y) * cell + cell * 0.16,
                        width: cell * 0.68, height: cell * 0.68)
        ctx.fill(Path(ellipseIn: fr), with: .color(Color(red: 1.0, green: 0.3, blue: 0.3)))

        guard !game.snake.isEmpty else { return }
        let n = game.snake.count
        for i in stride(from: n - 1, through: 0, by: -1) {
            let prev = game.prevSnake[min(i, game.prevSnake.count - 1)]
            let cur = game.snake[i]
            let x = (CGFloat(prev.x) + CGFloat(cur.x - prev.x) * t) * cell
            let y = (CGFloat(prev.y) + CGFloat(cur.y - prev.y) * t) * cell
            let inset = i == 0 ? cell * 0.06 : cell * 0.11
            let rect = CGRect(x: x + inset, y: y + inset, width: cell - inset * 2, height: cell - inset * 2)
            let shade = i % 2 == 0
            let bodyColor = Color(red: shade ? 0.18 : 0.22, green: shade ? 0.82 : 0.88, blue: 0.42)
            ctx.fill(Path(roundedRect: rect, cornerRadius: cell * 0.32),
                     with: .color(i == 0 ? Color(red: 0.68, green: 1.0, blue: 0.62) : bodyColor))
        }

        let headPrev = game.prevSnake.first ?? game.snake[0]
        let hx = (CGFloat(headPrev.x) + CGFloat(game.snake[0].x - headPrev.x) * t) * cell + cell / 2
        let hy = (CGFloat(headPrev.y) + CGFloat(game.snake[0].y - headPrev.y) * t) * cell + cell / 2
        let d = game.direction.delta
        let perpX = -d.y, perpY = d.x
        for s in [-1.0, 1.0] {
            let ex = hx + CGFloat(d.x) * cell * 0.16 + CGFloat(perpX) * cell * 0.2 * CGFloat(s)
            let ey = hy + CGFloat(d.y) * cell * 0.16 + CGFloat(perpY) * cell * 0.2 * CGFloat(s)
            ctx.fill(Path(ellipseIn: CGRect(x: ex - 2.5, y: ey - 2.5, width: 5, height: 5)),
                     with: .color(.black.opacity(0.85)))
        }
    }

    // MARK: Оверлей (старт / пауза / конец)

    private var overlay: some View {
        VStack(spacing: 16) {
            if game.isGameOver {
                Text("Игра окончена")
                    .font(.title.bold())
                    .foregroundColor(.white)
                Text("Счёт: \(game.score)")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.6))
                actionButton("Ещё раз") { game.start() }
            } else if game.isPaused {
                Text("Пауза")
                    .font(.title.bold())
                    .foregroundColor(.white)
                actionButton("Продолжить") { game.resume() }
            } else {
                Text("ЗМЕЙКА")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                Text("Собирай яблоки и не врезайся!")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                actionButton("Играть") { game.start() }
            }
        }
        .padding(28)
        .glassCard()
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            SFX.click()
            action()
        } label: {
            Text(title)
        }
        .buttonStyle(GlassButtonStyle(filled: true))
    }
}
