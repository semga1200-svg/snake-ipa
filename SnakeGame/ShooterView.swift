import SwiftUI
import SceneKit
import UIKit
import Combine

// MARK: - Vector helpers

private func + (l: SCNVector3, r: SCNVector3) -> SCNVector3 { SCNVector3(l.x + r.x, l.y + r.y, l.z + r.z) }
private func - (l: SCNVector3, r: SCNVector3) -> SCNVector3 { SCNVector3(l.x - r.x, l.y - r.y, l.z - r.z) }
private func * (v: SCNVector3, s: Float) -> SCNVector3 { SCNVector3(v.x * s, v.y * s, v.z * s) }
private func length(_ v: SCNVector3) -> Float { sqrt(v.x * v.x + v.y * v.y + v.z * v.z) }
private func clampF(_ v: Float, _ lo: Float, _ hi: Float) -> Float { max(lo, min(hi, v)) }

// MARK: - Shared game state

final class ShooterState: ObservableObject {
    @Published var score: Int = 0
    @Published var hitMarker: Bool = false

    // input (written from UI, read from render thread)
    var yaw: Float = 0
    var pitch: Float = 0
    var moveForward = false
    var moveBack = false
    var moveLeft = false
    var moveRight = false
    var fireRequested = false
}

// MARK: - Bot

private final class Bot {
    let node: SCNNode
    var velocity: SCNVector3
    var alive: Bool = true
    var respawnAt: TimeInterval = 0
    let baseY: Float

    init(node: SCNNode, velocity: SCNVector3, baseY: Float) {
        self.node = node
        self.velocity = velocity
        self.baseY = baseY
    }
}

// MARK: - Scene controller

final class ShooterController: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let weaponNode = SCNNode()
    private var bots: [Bot] = []
    private weak var view: SCNView?
    private let state: ShooterState

    private var lastTime: TimeInterval = 0
    private var muzzleUntil: TimeInterval = 0
    private var muzzleLight: SCNLight?
    private var lastShotTime: TimeInterval = -1

    init(state: ShooterState) {
        self.state = state
        super.init()
        setupScene()
    }

    func attach(to view: SCNView) {
        self.view = view
        view.scene = scene
        view.pointOfView = cameraNode
        view.delegate = self
        view.backgroundColor = UIColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1)
        view.isPlaying = true
        view.preferredFramesPerSecond = 60
        view.antialiasingMode = .multisampling2X
    }

    private func setupScene() {
        scene.background.contents = UIColor(red: 0.50, green: 0.72, blue: 0.95, alpha: 1)

        // Lights
        let ambient = SCNNode()
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = UIColor(white: 0.55, alpha: 1)
        ambient.light = ambientLight
        scene.rootNode.addChildNode(ambient)

        let sun = SCNNode()
        let sunLight = SCNLight()
        sunLight.type = .directional
        sunLight.color = UIColor(white: 0.95, alpha: 1)
        sunLight.castsShadow = true
        sun.light = sunLight
        sun.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
        scene.rootNode.addChildNode(sun)

        // Floor
        let floor = SCNFloor()
        floor.reflectivity = 0
        let floorMat = SCNMaterial()
        floorMat.diffuse.contents = UIColor(red: 0.28, green: 0.34, blue: 0.28, alpha: 1)
        floor.materials = [floorMat]
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(floorNode)

        // Obstacles / cover
        addBox(at: SCNVector3(-4, 0.75, -8), size: SCNVector3(1.5, 1.5, 1.5), color: UIColor(red: 0.45, green: 0.45, blue: 0.48, alpha: 1))
        addBox(at: SCNVector3(5, 0.5, -10), size: SCNVector3(2.0, 1.0, 1.0), color: UIColor(red: 0.40, green: 0.42, blue: 0.46, alpha: 1))
        addBox(at: SCNVector3(0, 1.0, -14), size: SCNVector3(3.0, 2.0, 0.6), color: UIColor(red: 0.42, green: 0.40, blue: 0.38, alpha: 1))
        addBox(at: SCNVector3(-7, 0.5, -5), size: SCNVector3(1.0, 1.0, 3.0), color: UIColor(red: 0.38, green: 0.43, blue: 0.38, alpha: 1))
        addBox(at: SCNVector3(7, 0.75, -6), size: SCNVector3(1.2, 1.5, 1.2), color: UIColor(red: 0.46, green: 0.44, blue: 0.42, alpha: 1))

        // Camera (player)
        let cam = SCNCamera()
        cam.zNear = 0.05
        cam.zFar = 200
        cam.fieldOfView = 70
        cameraNode.camera = cam
        cameraNode.position = SCNVector3(0, 1.6, 0)
        scene.rootNode.addChildNode(cameraNode)

        setupWeapon()
        setupBots()
    }

    private func addBox(at pos: SCNVector3, size: SCNVector3, color: UIColor) {
        let box = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: 0.02)
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        box.materials = [mat]
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(pos.x, pos.y, pos.z)
        scene.rootNode.addChildNode(node)
    }

    // MARK: - Weapon and hands (first person, attached to camera)

    private func setupWeapon() {
        weaponNode.position = SCNVector3(0.18, -0.22, -0.45)

        let gunMat = SCNMaterial()
        gunMat.diffuse.contents = UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)
        gunMat.metalness.contents = 0.6
        gunMat.roughness.contents = 0.35

        let darkMat = SCNMaterial()
        darkMat.diffuse.contents = UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)

        let skinMat = SCNMaterial()
        skinMat.diffuse.contents = UIColor(red: 0.86, green: 0.70, blue: 0.58, alpha: 1)
        skinMat.roughness.contents = 0.8

        let sleeveMat = SCNMaterial()
        sleeveMat.diffuse.contents = UIColor(red: 0.22, green: 0.35, blue: 0.22, alpha: 1)

        // Barrel
        let barrel = SCNBox(width: 0.045, height: 0.045, length: 0.42, chamferRadius: 0.01)
        barrel.materials = [gunMat]
        let barrelNode = SCNNode(geometry: barrel)
        barrelNode.position = SCNVector3(0, 0.02, -0.18)
        weaponNode.addChildNode(barrelNode)

        // Receiver/body
        let body = SCNBox(width: 0.07, height: 0.09, length: 0.22, chamferRadius: 0.015)
        body.materials = [gunMat]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, -0.01, 0.02)
        weaponNode.addChildNode(bodyNode)

        // Grip
        let grip = SCNBox(width: 0.045, height: 0.12, length: 0.06, chamferRadius: 0.01)
        grip.materials = [darkMat]
        let gripNode = SCNNode(geometry: grip)
        gripNode.position = SCNVector3(0, -0.1, 0.06)
        gripNode.eulerAngles = SCNVector3(0.35, 0, 0)
        weaponNode.addChildNode(gripNode)

        // Magazine
        let mag = SCNBox(width: 0.035, height: 0.11, length: 0.05, chamferRadius: 0.008)
        mag.materials = [darkMat]
        let magNode = SCNNode(geometry: mag)
        magNode.position = SCNVector3(0, -0.12, -0.02)
        magNode.eulerAngles = SCNVector3(0.15, 0, 0)
        weaponNode.addChildNode(magNode)

        // Sight
        let sight = SCNBox(width: 0.01, height: 0.025, length: 0.02, chamferRadius: 0.002)
        sight.materials = [darkMat]
        let sightNode = SCNNode(geometry: sight)
        sightNode.position = SCNVector3(0, 0.06, -0.04)
        weaponNode.addChildNode(sightNode)

        // Right arm / hand (grip)
        let rSleeve = SCNCapsule(capRadius: 0.028, height: 0.22)
        rSleeve.materials = [sleeveMat]
        let rSleeveNode = SCNNode(geometry: rSleeve)
        rSleeveNode.position = SCNVector3(0.06, -0.16, 0.18)
        rSleeveNode.eulerAngles = SCNVector3(1.25, 0.15, -0.2)
        weaponNode.addChildNode(rSleeveNode)

        let rHand = SCNBox(width: 0.045, height: 0.035, length: 0.07, chamferRadius: 0.01)
        rHand.materials = [skinMat]
        let rHandNode = SCNNode(geometry: rHand)
        rHandNode.position = SCNVector3(0.02, -0.11, 0.08)
        rHandNode.eulerAngles = SCNVector3(0.4, 0.1, 0)
        weaponNode.addChildNode(rHandNode)

        // Left arm / hand (supporting barrel)
        let lSleeve = SCNCapsule(capRadius: 0.026, height: 0.26)
        lSleeve.materials = [sleeveMat]
        let lSleeveNode = SCNNode(geometry: lSleeve)
        lSleeveNode.position = SCNVector3(-0.12, -0.14, 0.0)
        lSleeveNode.eulerAngles = SCNVector3(1.35, -0.45, 0.35)
        weaponNode.addChildNode(lSleeveNode)

        let lHand = SCNBox(width: 0.042, height: 0.03, length: 0.08, chamferRadius: 0.01)
        lHand.materials = [skinMat]
        let lHandNode = SCNNode(geometry: lHand)
        lHandNode.position = SCNVector3(-0.04, -0.06, -0.12)
        lHandNode.eulerAngles = SCNVector3(0.2, -0.3, 0.2)
        weaponNode.addChildNode(lHandNode)

        // Muzzle flash light (hidden by default)
        let flashNode = SCNNode()
        let flashLight = SCNLight()
        flashLight.type = .omni
        flashLight.color = UIColor(red: 1.0, green: 0.8, blue: 0.3, alpha: 1)
        flashLight.intensity = 0
        flashNode.light = flashLight
        flashNode.position = SCNVector3(0, 0.02, -0.42)
        weaponNode.addChildNode(flashNode)
        muzzleLight = flashLight

        cameraNode.addChildNode(weaponNode)
    }

    // MARK: - Bots

    private func setupBots() {
        let positions: [SCNVector3] = [
            SCNVector3(-3, 0, -8),
            SCNVector3(4, 0, -10),
            SCNVector3(-6, 0, -14),
            SCNVector3(2, 0, -16),
            SCNVector3(6, 0, -7),
            SCNVector3(-1, 0, -12)
        ]
        for (i, p) in positions.enumerated() {
            let botNode = makeBot(index: i)
            botNode.position = p
            scene.rootNode.addChildNode(botNode)
            let vel = SCNVector3(Float.random(in: -0.6...0.6), 0, Float.random(in: -0.4...0.4))
            bots.append(Bot(node: botNode, velocity: vel, baseY: 0))
        }
    }

    private func makeBot(index: Int) -> SCNNode {
        let root = SCNNode()
        root.name = "bot_\(index)"

        let bodyMat = SCNMaterial()
        let colors: [UIColor] = [
            UIColor(red: 0.75, green: 0.22, blue: 0.22, alpha: 1),
            UIColor(red: 0.22, green: 0.45, blue: 0.75, alpha: 1),
            UIColor(red: 0.70, green: 0.55, blue: 0.20, alpha: 1),
            UIColor(red: 0.45, green: 0.25, blue: 0.55, alpha: 1)
        ]
        bodyMat.diffuse.contents = colors[index % colors.count]

        let headMat = SCNMaterial()
        headMat.diffuse.contents = UIColor(red: 0.92, green: 0.78, blue: 0.65, alpha: 1)

        let darkMat = SCNMaterial()
        darkMat.diffuse.contents = UIColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1)

        // Torso
        let torso = SCNBox(width: 0.5, height: 0.7, length: 0.28, chamferRadius: 0.05)
        torso.materials = [bodyMat]
        let torsoNode = SCNNode(geometry: torso)
        torsoNode.position = SCNVector3(0, 1.05, 0)
        root.addChildNode(torsoNode)

        // Head
        let head = SCNSphere(radius: 0.22)
        head.materials = [headMat]
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 1.58, 0)
        root.addChildNode(headNode)

        // Eyes (so it's clearly a character)
        let eye = SCNSphere(radius: 0.035)
        eye.materials = [darkMat]
        let le = SCNNode(geometry: eye); le.position = SCNVector3(-0.07, 1.62, 0.19)
        let re = SCNNode(geometry: eye); re.position = SCNVector3(0.07, 1.62, 0.19)
        root.addChildNode(le); root.addChildNode(re)

        // Legs
        let legGeo = SCNBox(width: 0.16, height: 0.7, length: 0.18, chamferRadius: 0.03)
        legGeo.materials = [darkMat]
        let ll = SCNNode(geometry: legGeo); ll.position = SCNVector3(-0.12, 0.35, 0)
        let rl = SCNNode(geometry: legGeo); rl.position = SCNVector3(0.12, 0.35, 0)
        root.addChildNode(ll); root.addChildNode(rl)

        // Small weapon in bot hands
        let bGun = SCNBox(width: 0.06, height: 0.06, length: 0.35, chamferRadius: 0.01)
        bGun.materials = [darkMat]
        let bGunNode = SCNNode(geometry: bGun)
        bGunNode.position = SCNVector3(0.28, 1.05, 0.18)
        bGunNode.eulerAngles = SCNVector3(0, 0.2, 0)
        root.addChildNode(bGunNode)

        return root
    }

    // MARK: - Per-frame update

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt: Float
        if lastTime == 0 { dt = 1.0 / 60.0 } else { dt = Float(min(time - lastTime, 0.1)) }
        lastTime = time

        // Camera rotation from input
        let yaw = state.yaw
        let pitch = clampF(state.pitch, -1.2, 1.2)
        cameraNode.eulerAngles = SCNVector3(pitch, yaw, 0)

        // Movement
        let speed: Float = 3.5 * dt
        let forward = SCNVector3(sin(yaw), 0, -cos(yaw))
        let right = SCNVector3(cos(yaw), 0, sin(yaw))
        var move = SCNVector3(0, 0, 0)
        if state.moveForward { move = move + forward * speed }
        if state.moveBack { move = move - forward * speed }
        if state.moveRight { move = move + right * speed }
        if state.moveLeft { move = move - right * speed }
        var pos = cameraNode.position + move
        pos.x = clampF(pos.x, -12, 12)
        pos.z = clampF(pos.z, -20, 4)
        pos.y = 1.6
        cameraNode.position = pos

        // Fire
        if state.fireRequested {
            state.fireRequested = false
            if time - lastShotTime > 0.18 { // fire rate limit
                lastShotTime = time
                performShot(at: time)
            }
        }

        // Muzzle flash off
        if time > muzzleUntil {
            muzzleLight?.intensity = 0
        }

        // Bots
        updateBots(time: time, dt: dt)

        // Subtle weapon sway
        let t = Float(time)
        weaponNode.position = SCNVector3(0.18 + sin(t * 1.5) * 0.002, -0.22 + sin(t * 2.0) * 0.003, -0.45)
    }

    private func updateBots(time: TimeInterval, dt: Float) {
        for bot in bots {
            if !bot.alive {
                if time >= bot.respawnAt { respawn(bot: bot) }
                continue
            }
            var p = bot.node.position
            p = p + bot.velocity * dt
            if p.x < -11 || p.x > 11 { bot.velocity.x *= -1; p.x = clampF(p.x, -11, 11) }
            if p.z < -19 || p.z > -2 { bot.velocity.z *= -1; p.z = clampF(p.z, -19, -2) }
            // slight drift
            if Int(time * 10) % 37 == 0 {
                bot.velocity.x += Float.random(in: -0.2...0.2)
                bot.velocity.z += Float.random(in: -0.2...0.2)
                let sp = max(0.2, min(1.2, length(bot.velocity)))
                if length(bot.velocity) > 0.001 { bot.velocity = bot.velocity * (sp / length(bot.velocity)) }
            }
            p.y = bot.baseY
            bot.node.position = p

            // face player
            let toPlayer = cameraNode.position - p
            let angle = atan2(toPlayer.x, toPlayer.z)
            bot.node.eulerAngles = SCNVector3(0, angle, 0)
        }
    }

    private func performShot(at time: TimeInterval) {
        // muzzle flash & recoil
        muzzleLight?.intensity = 800
        muzzleUntil = time + 0.05
        let original = weaponNode.position
        weaponNode.position = SCNVector3(original.x, original.y + 0.01, original.z + 0.03)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.weaponNode.position = original
        }

        DispatchQueue.main.async {
            SFX.click()
            Haptics.light()
        }

        guard let view = view else { return }
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let hits = view.hitTest(center, options: [
            SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue,
            SCNHitTestOption.ignoreHiddenNodes: true
        ])
        for hit in hits {
            if let bot = botFor(node: hit.node), bot.alive {
                kill(bot: bot, at: time)
                break
            }
        }
    }

    private func botFor(node: SCNNode) -> Bot? {
        var n: SCNNode? = node
        while let cur = n {
            if let name = cur.name, name.hasPrefix("bot_") {
                return bots.first(where: { $0.node === cur })
            }
            n = cur.parent
        }
        return nil
    }

    private func kill(bot: Bot, at time: TimeInterval) {
        guard bot.alive else { return }
        bot.alive = false
        bot.respawnAt = time + 2.0

        DispatchQueue.main.async {
            self.state.score += 1
            self.state.hitMarker = true
            SFX.pop()
            Haptics.medium()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                self.state.hitMarker = false
            }
        }

        let fall = SCNAction.rotateBy(x: CGFloat.pi / 2, y: 0, z: 0, duration: 0.25)
        let fade = SCNAction.fadeOut(duration: 0.25)
        let hide = SCNAction.run { node in node.isHidden = true }
        bot.node.runAction(SCNAction.sequence([SCNAction.group([fall, fade]), hide]))
    }

    private func respawn(bot: Bot) {
        bot.alive = true
        bot.node.removeAllActions()
        bot.node.isHidden = false
        bot.node.opacity = 0
        bot.node.eulerAngles = SCNVector3Zero
        let x = Float.random(in: -10...10)
        let z = Float.random(in: -18 ... -4)
        bot.node.position = SCNVector3(x, bot.baseY, z)
        bot.velocity = SCNVector3(Float.random(in: -0.8...0.8), 0, Float.random(in: -0.6...0.6))
        bot.node.runAction(SCNAction.fadeIn(duration: 0.2))
    }
}

// MARK: - SwiftUI wrapper

struct ShooterSceneView: UIViewRepresentable {
    @ObservedObject var state: ShooterState

    func makeCoordinator() -> ShooterController {
        ShooterController(state: state)
    }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero)
        context.coordinator.attach(to: v)
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

// MARK: - Controls

private struct HoldButton: View {
    let system: String
    let onChange: (Bool) -> Void
    @State private var pressed = false

    var body: some View {
        Image(systemName: system)
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 54, height: 54)
            .background(Circle().fill(pressed ? Color.white.opacity(0.35) : Color.white.opacity(0.15)))
            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed { pressed = true; onChange(true) }
                    }
                    .onEnded { _ in
                        pressed = false; onChange(false)
                    }
            )
    }
}

// MARK: - Main shooter view

struct ShooterView: View {
    @StateObject private var state = ShooterState()
    @State private var appeared = false
    @State private var dragStartYaw: Float = 0
    @State private var dragStartPitch: Float = 0
    @State private var isDragging = false

    var body: some View {
        ZStack {
            ShooterSceneView(state: state)
                .ignoresSafeArea()
                .gesture(lookGesture)

            // Crosshair
            VStack(spacing: 4) {
                Rectangle().fill(Color.white.opacity(0.9)).frame(width: 2, height: 10)
                HStack(spacing: 4) {
                    Rectangle().fill(Color.white.opacity(0.9)).frame(width: 10, height: 2)
                    Circle().stroke(Color.white.opacity(0.9), lineWidth: 2).frame(width: 5, height: 5)
                    Rectangle().fill(Color.white.opacity(0.9)).frame(width: 10, height: 2)
                }
                Rectangle().fill(Color.white.opacity(0.9)).frame(width: 2, height: 10)
            }
            .opacity(state.hitMarker ? 0.0 : 0.95)
            .overlay(
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.red)
                    .opacity(state.hitMarker ? 1 : 0)
            )

            // HUD & controls
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FPS")
                            .font(.caption).foregroundColor(.white.opacity(0.7))
                        Text("Счёт: \(state.score)")
                            .font(.title3.bold()).foregroundColor(.white)
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Spacer()
                    Text("Тяни для обзора")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                Spacer()

                HStack(alignment: .bottom) {
                    // Movement pad
                    VStack(spacing: 6) {
                        HoldButton(system: "chevron.up") { state.moveForward = $0 }
                        HStack(spacing: 6) {
                            HoldButton(system: "chevron.left") { state.moveLeft = $0 }
                            HoldButton(system: "chevron.down") { state.moveBack = $0 }
                            HoldButton(system: "chevron.right") { state.moveRight = $0 }
                        }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Spacer()

                    // Fire button
                    Button {
                        state.fireRequested = true
                        SFX.click()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(gradient: Gradient(colors: [Color.red, Color.orange]), startPoint: .top, endPoint: .bottom))
                                .frame(width: 80, height: 80)
                            Image(systemName: "scope")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 2))
                        .shadow(color: .red.opacity(0.45), radius: 10, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 100) // above tab bar
            }
        }
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.35)) { appeared = true } }
    }

    private var lookGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                if !isDragging {
                    isDragging = true
                    dragStartYaw = state.yaw
                    dragStartPitch = state.pitch
                }
                let sens: Float = 0.0055
                state.yaw = dragStartYaw - Float(v.translation.width) * sens
                state.pitch = max(-1.15, min(1.15, dragStartPitch - Float(v.translation.height) * sens))
            }
            .onEnded { _ in
                isDragging = false
            }
    }
}