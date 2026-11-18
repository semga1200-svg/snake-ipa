import SwiftUI

// MARK: - Model

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
    @Published var food = Cell(x: 5, y: 5)
    @Published var direction: Direction = .right
    @Published var isRunning = false
    @Published var isGameOver = false
    @Published var isPaused = false
    @Published var score = 0
    @Published var best = UserDefaults.standard.integer(forKey: "bestScore")

    private var pendingDirection: Direction = .right
    private var timer: Timer?

    var tickInterval: TimeInterval {
        max(0.07, 0.18 - Double(score) * 0.004)
    }

    init() {
        reset()
    }

    deinit {
        timer?.invalidate()
    }

    func reset() {
        snake = [Cell(x: 9, y: 13), Cell(x: 8, y: 13), Cell(x: 7, y: 13)]
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
        guard isRunning else { return }
        if newDirection.isOpposite(to: direction) { return }
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

        snake.insert(next, at: 0)
        if next == food {
            score += 1
            if score > best {
                best = score
                UserDefaults.standard.set(best, forKey: "bestScore")
            }
            spawnFood()
            scheduleTimer() // speed up
        } else {
            snake.removeLast()
        }
    }

    private func gameOver() {
        isRunning = false
        isGameOver = true
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

// MARK: - View

struct GameView: View {
    @StateObject private var game = GameModel()
    @Environment(\.scenePhase) private var scenePhase

    private let background = Color(red: 0.06, green: 0.09, blue: 0.16)
    private let boardColor = Color(red: 0.09, green: 0.13, blue: 0.22)
    private let snakeColor = Color(red: 0.13, green: 0.77, blue: 0.37)
    private let headColor = Color(red: 0.55, green: 0.95, blue: 0.55)

    var body: some View {
        VStack(spacing: 14) {
            header
            board
            Text("Свайп по полю — поворот змейки")
                .font(.footnote)
                .foregroundColor(.gray)
        }
        .padding(16)
        .background(background.ignoresSafeArea())
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                game.pause()
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("СЧЁТ")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("\(game.score)")
                    .font(.title2.bold())
                    .foregroundColor(.white)
            }
            Spacer()
            if game.isRunning {
                Button {
                    game.pause()
                } label: {
                    Image(systemName: "pause.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("РЕКОРД")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("\(game.best)")
                    .font(.title2.bold())
                    .foregroundColor(.white)
            }
        }
    }

    private var board: some View {
        GeometryReader { geo in
            let cell = min(geo.size.width / CGFloat(GameModel.cols),
                           geo.size.height / CGFloat(GameModel.rows))
            let w = cell * CGFloat(GameModel.cols)
            let h = cell * CGFloat(GameModel.rows)
            ZStack {
                Canvas { context, _ in
                    draw(in: context, cell: cell, width: w, height: h)
                }
                .frame(width: w, height: h)

                if !game.isRunning {
                    overlay
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .gesture(
            DragGesture(minimumDistance: 15)
                .onEnded { value in
                    let t = value.translation
                    if abs(t.width) > abs(t.height) {
                        game.turn(t.width > 0 ? .right : .left)
                    } else {
                        game.turn(t.height > 0 ? .down : .up)
                    }
                }
        )
    }

    private func draw(in context: GraphicsContext, cell: CGFloat, width: CGFloat, height: CGFloat) {
        let boardRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.fill(Path(roundedRect: boardRect, cornerRadius: 12), with: .color(boardColor))

        let foodRect = CGRect(x: CGFloat(game.food.x) * cell + 3,
                              y: CGFloat(game.food.y) * cell + 3,
                              width: cell - 6, height: cell - 6)
        context.fill(Path(ellipseIn: foodRect), with: .color(.red))

        for (index, part) in game.snake.enumerated() {
            let rect = CGRect(x: CGFloat(part.x) * cell + 1.5,
                              y: CGFloat(part.y) * cell + 1.5,
                              width: cell - 3, height: cell - 3)
            let color = index == 0 ? headColor : snakeColor
            context.fill(Path(roundedRect: rect, cornerRadius: cell * 0.25),
                         with: .color(color))
        }
    }

    private var overlay: some View {
        VStack(spacing: 16) {
            if game.isGameOver {
                Text("Игра окончена")
                    .font(.title.bold())
                    .foregroundColor(.white)
                Text("Счёт: \(game.score)")
                    .font(.headline)
                    .foregroundColor(.gray)
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
                    .foregroundColor(.gray)
                actionButton("Играть") { game.start() }
            }
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.black)
                .padding(.horizontal, 36)
                .padding(.vertical, 12)
                .background(Color.green, in: Capsule())
        }
    }
}