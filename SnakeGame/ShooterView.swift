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
    @Published var playerHP: Int = 100
    @Published var maxHP: Int = 100
    @Published var hitMarker: Bool = false
    @Published var damageFlash: Bool = false
    @Published var isDead: Bool = false
    @Published var showCheatMenu: Bool = false

    // cheats
    @Published var godMode: Bool = false
    @Published var rapidFire: Bool = false
    @Published var freezeBots: Bool = false

    let cheatsUnlocked: Bool

    // input (written from UI, read from render thread)
    var yaw: Float = 0
    var pitch: Float = 0
    var moveForward = false
    var moveBack = false
    var moveLeft = false
    var moveRight = false
    var fireRequested = false
    var restartRequested = false

    init(cheatsUnlocked: Bool = false, showCheatMenu: Bool = false) {
        self.cheatsUnlocked = cheatsUnlocked
        self.showCheatMenu = showCheatMenu
    }
}

// MARK: - Bot

private final class Bot {
    let node: SCNNode
    var velocity: SCNVector3
    var alive: Bool = true
    var respawnAt: TimeInterval = 0
    let baseY: Float
    var nextShotTime: TimeInterval = 0

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

        // More walls / cover
        addBox(at: SCNVector3(-4, 0.75, -8), size: SCNVector3(1.5, 1.5, 1.5), color: UIColor(red: 0.45, green: 0.45, blue: 0.48, alpha: 1))
        addBox(at: SCNVector3(5, 0.5, -10), size: SCNVector3(2.0, 1.0, 1.0), color: UIColor(red: 0.40, green: 0.42, blue: 0.46, alpha: 1))
        addBox(at: SCNVector3(0, 1.0, -14), size: SCNVector3(3.0, 2.0, 0.6), color: UIColor(red: 0.42, green: 0.40, blue: 0.38, alpha: 1))
        addBox(at: SCNVector3(-7, 0.5, -5), size: SCNVector3(1.0, 1.0, 3.0), color: UIColor(red: 0.38, green: 0.43, blue: 0.38, alpha: 1))
        addBox(at: SCNVector3(7, 0.75, -6), size: SCNVector3(1.2, 1.5, 1.2), color: UIColor(red: 0.46, green: 0.44, blue: 0.42, alpha: 1))
        addBox(at: SCNVector3(-9, 1.0, -11), size: SCNVector3(2.0, 2.0, 0.8), color: UIColor(red: 0.43, green: 0.43, blue: 0.46, alpha: 1))
        addBox(at: SCNVector3(9, 1.0, -12), size: SCNVector3(2.0, 2.0, 0.8), color: UIColor(red: 0.43, green: 0.43, blue: 0.46, alpha: 1))
        addBox(at: SCNVector3(-2, 0.6, -4), size: SCNVector3(1.4, 1.2, 1.4), color: UIColor(red: 0.47, green: 0.45, blue: 0.43, alpha: 1))
        addBox(at: SCNVector3(3, 0.6, -3), size: SCNVector3(1.6, 1.2, 1.0), color: UIColor(red: 0.44, green: 0.46, blue: 0.44, alpha: 1))
        addBox(at: SCNVector3(-5, 0.75, -16), size: SCNVector3(1.2, 1.5, 2.5), color: UIColor(red: 0.40, green: 0.41, blue: 0.45, alpha: 1))
        addBox(at: SCNVector3(6, 0.75, -17), size: SCNVector3(1.2, 1.5, 2.5), color: UIColor(red: 0.40, green: 0.41, blue: 0.45, alpha: 1))
        addBox(at: SCNVector3(0, 0.5, -19), size: SCNVector3(4.0, 1.0, 0.8), color: UIColor(red: 0.41, green: 0.39, blue: 0.37, alpha: 1))
        addBox(at: SCNVector3(-10, 0.6, -7), size: SCNVector3(0.8, 1.2, 2.0), color: UIColor(red: 0.46, green: 0.44, blue: 0.46, alpha: 1))
        addBox(at: SCNVector3(10, 0.6, -8), size: SCNVector3(0.8, 1.2, 2.0), color: UIColor(red: 0.46, green: 0.44, blue: 0.46, alpha: 1))
        addBox(at: SCNVector3(-1, 1.2, -11), size: SCNVector3(1.0, 2.4, 1.0), color: UIColor(red: 0.39, green: 0.42, blue: 0.40, alpha: 1))
        addBox(at: SCNVector3(8, 0.5, -2), size: SCNVector3(2.0, 1.0, 1.0), color: UIColor(red: 0.44, green: 0.45, blue: 0.43, alpha: 1))
        addBox(at: SCNVector3(-8, 0.5, -2), size: SCNVector3(2.0, 1.0, 1.0), color: UIColor(red: 0.44, green: 0.45, blue: 0.43, alpha: 1))

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

    // MARK: - Weapon and hands (first person)

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

        let barrel = SCNBox(width: 0.045, height: 0.045, length: 0.42, chamferRadius: 0.01)
        barrel.materials = [gunMat]
        let barrelNode = SCNNode(geometry: barrel)
        barrelNode.position = SCNVector3(0, 0.02, -0.18)
        weaponNode.addChildNode(barrelNode)

        let body = SCNBox(width: 0.07, height: 0.09, length: 0.22, chamferRadius: 0.015)
        body.materials = [gunMat]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, -0.01, 0.02)
        weaponNode.addChildNode(bodyNode)

        let grip = SCNBox(width: 0.045, height: 0.12, length: 0.06, chamferRadius: 0.01)
        grip.materials = [darkMat]
        let gripNode = SCNNode(geometry: grip)
        gripNode.position = SCNVector3(0, -0.1, 0.06)
        gripNode.eulerAngles = SCNVector3(0.35, 0, 0)
        weaponNode.addChildNode(gripNode)

        let mag = SCNBox(width: 0.035, height: 0.11, length: 0.05, chamferRadius: 0.008)
        mag.materials = [darkMat]
        let magNode = SCNNode(geometry: mag)
        magNode.position = SCNVector3(0, -0.12, -0.02)
        magNode.eulerAngles = SCNVector3(0.15, 0, 0)
        weaponNode.addChildNode(magNode)

        let sight = SCNBox(width: 0.01, height: 0.025, length: 0.02, chamferRadius: 0.002)
        sight.materials = [darkMat]
        let sightNode = SCNNode(geometry: sight)
        sightNode.position = SCNVector3(0, 0.06, -0.04)
        weaponNode.addChildNode(sightNode)

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
            SCNVector3(-1, 0, -12),
            SCNVector3(-8, 0, -9),
            SCNVector3(8, 0, -15)
        ]
        for (i, p) in positions.enumerated() {
            let botNode = makeBot(index: i)
            botNode.position = p
            scene.rootNode.addChildNode(botNode)
            let vel = SCNVector3(Float.random(in: -0.7...0.7), 0, Float.random(in: -0.5...0.5))
            let bot = Bot(node: botNode, velocity: vel, baseY: 0)
            bot.nextShotTime = Double.random(in: 1.0...3.0)
            bots.append(bot)
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

        let torso = SCNBox(width: 0.5, height: 0.7, length: 0.28, chamferRadius: 0.05)
        torso.materials = [bodyMat]
        let torsoNode = SCNNode(geometry: torso)
        torsoNode.position = SCNVector3(0, 1.05, 0)
        root.addChildNode(torsoNode)

        let head = SCNSphere(radius: 0.22)
        head.materials = [headMat]
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 1.58, 0)
        root.addChildNode(headNode)

        let eye = SCNSphere(radius: 0.035)
        eye.materials = [darkMat]
        let le = SCNNode(geometry: eye); le.position = SCNVector3(-0.07, 1.62, 0.19)
        let re = SCNNode(geometry: eye); re.position = SCNVector3(0.07, 1.62, 0.19)
        root.addChildNode(le); root.addChildNode(re)

        let legGeo = SCNBox(width: 0.16, height: 0.7, length: 0.18, chamferRadius: 0.03)
        legGeo.materials = [darkMat]
        let ll = SCNNode(geometry: legGeo); ll.position = SCNVector3(-0.12, 0.35, 0)
        let rl = SCNNode(geometry: legGeo); rl.position = SCNVector3(0.12, 0.35, 0)
        root.addChildNode(ll); root.addChildNode(rl)

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

        // Restart
        if state.restartRequested {
            state.restartRequested = false
            DispatchQueue.main.async { [weak self] in
                self?.resetGame()
            }
        }

        let dead = state.isDead
        let frozen = state.freezeBots

        // Camera rotation
        let yaw = state.yaw
        let pitch = clampF(state.pitch, -1.2, 1.2)
        cameraNode.eulerAngles = SCNVector3(pitch, yaw, 0)

        // Movement (disabled when dead)
        if !dead {
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
        }

        // Fire
        if state.fireRequested && !dead {
            state.fireRequested = false
            let cooldown = state.rapidFire ? 0.08 : 0.22
            if time - lastShotTime > cooldown {
                lastShotTime = time
                performShot(at: time)
            }
        } else if state.fireRequested {
            state.fireRequested = false
        }

        if time > muzzleUntil { muzzleLight?.intensity = 0 }

        // Bots
        updateBots(time: time, dt: dt, frozen: frozen, playerDead: dead)

        // Weapon sway
        let t = Float(time)
        weaponNode.position = SCNVector3(0.18 + sin(t * 1.5) * 0.002, -0.22 + sin(t * 2.0) * 0.003, -0.45)
    }

    private func resetGame() {
        state.score = 0
        state.playerHP = state.maxHP
        state.isDead = false
        state.hitMarker = false
        state.damageFlash = false
        cameraNode.position = SCNVector3(0, 1.6, 0)
        state.yaw = 0
        state.pitch = 0
        lastShotTime = -1
        for (i, bot) in bots.enumerated() {
            bot.alive = true
            bot.node.removeAllActions()
            bot.node.isHidden = false
            bot.node.opacity = 1.0
            bot.node.eulerAngles = SCNVector3Zero
            let positions: [SCNVector3] = [
                SCNVector3(-3, 0, -8), SCNVector3(4, 0, -10), SCNVector3(-6, 0, -14), SCNVector3(2, 0, -16),
                SCNVector3(6, 0, -7), SCNVector3(-1, 0, -12), SCNVector3(-8, 0, -9), SCNVector3(8, 0, -15)
            ]
            bot.node.position = positions[i % positions.count]
            bot.velocity = SCNVector3(Float.random(in: -0.7...0.7), 0, Float.random(in: -0.5...0.5))
            bot.nextShotTime = Double.random(in: 1.0...3.0)
        }
    }

    private func updateBots(time: TimeInterval, dt: Float, frozen: Bool, playerDead: Bool) {
        for bot in bots {
            if !bot.alive {
                if time >= bot.respawnAt { respawn(bot: bot, time: time) }
                continue
            }
            var p = bot.node.position

            if !frozen {
                p = p + bot.velocity * dt
                if p.x < -11 || p.x > 11 { bot.velocity.x *= -1; p.x = clampF(p.x, -11, 11) }
                if p.z < -19 || p.z > -2 { bot.velocity.z *= -1; p.z = clampF(p.z, -19, -2) }
                if Int(time * 10) % 37 == 0 {
                    bot.velocity.x += Float.random(in: -0.2...0.2)
                    bot.velocity.z += Float.random(in: -0.2...0.2)
                    let sp = max(0.2, min(1.2, length(bot.velocity)))
                    if length(bot.velocity) > 0.001 { bot.velocity = bot.velocity * (sp / length(bot.velocity)) }
                }
            }

            p.y = bot.baseY
            bot.node.position = p

            // face player
            let toPlayer = cameraNode.position - p
            let angle = atan2(toPlayer.x, toPlayer.z)
            bot.node.eulerAngles = SCNVector3(0, angle, 0)

            // bot shooting
            if !frozen && !playerDead && time >= bot.nextShotTime {
                let dist = length(SCNVector3(toPlayer.x, 0, toPlayer.z))
                if dist < 18.0 {
                    botFire(bot: bot, distance: dist, time: time)
                } else {
                    bot.nextShotTime = time + Double.random(in: 0.8...1.6)
                }
            }
        }
    }

    private func botFire(bot: Bot, distance: Float, time: TimeInterval) {
        bot.nextShotTime = time + Double.random(in: 1.0...2.2)

        // simple hit chance: closer = more accurate
        let baseChance: Float = distance < 6 ? 0.55 : (distance < 12 ? 0.35 : 0.18)
        let hit = Float.random(in: 0...1) < baseChance

        // visual cue: small flash scale on bot gun (pulse)
        let pulse = SCNAction.sequence([
            SCNAction.scale(to: 1.15, duration: 0.05),
            SCNAction.scale(to: 1.0, duration: 0.08)
        ])
        bot.node.runAction(pulse)

        DispatchQueue.main.async { SFX.tick() }

        if hit && !state.godMode && !state.isDead {
            let damage = Int.random(in: 6...12)
            DispatchQueue.main.async {
                guard !self.state.isDead else { return }
                self.state.playerHP = max(0, self.state.playerHP - damage)
                self.state.damageFlash = true
                SFX.error()
                Haptics.medium()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.state.damageFlash = false
                }
                if self.state.playerHP <= 0 {
                    self.state.isDead = true
                    SFX.error()
                }
            }
        }
    }

    private func performShot(at time: TimeInterval) {
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
        bot.respawnAt = time + 2.5

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

    private func respawn(bot: Bot, time: TimeInterval) {
        bot.alive = true
        bot.node.removeAllActions()
        bot.node.isHidden = false
        bot.node.opacity = 0
        bot.node.eulerAngles = SCNVector3Zero
        let x = Float.random(in: -10...10)
        let z = Float.random(in: -18 ... -4)
        bot.node.position = SCNVector3(x, bot.baseY, z)
        bot.velocity = SCNVector3(Float.random(in: -0.8...0.8), 0, Float.random(in: -0.6...0.6))
        bot.nextShotTime = time + Double.random(in: 0.8...1.8)
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

// MARK: - Cheat menu

private struct CheatMenuView: View {
    @ObservedObject var state: ShooterState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ЧИТ-МЕНЮ")
                    .font(.headline).bold().foregroundColor(.white)
                Spacer()
                Button { state.showCheatMenu = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            Toggle(isOn: $state.godMode) { Text("Бессмертие").foregroundColor(.white) }
            Toggle(isOn: $state.rapidFire) { Text("Быстрая стрельба").foregroundColor(.white) }
            Toggle(isOn: $state.freezeBots) { Text("Заморозить ботов").foregroundColor(.white) }
            Divider().background(Color.white.opacity(0.3))
            HStack(spacing: 10) {
                Button("+100 очков") {
                    state.score += 100
                    SFX.pop()
                }
                .buttonStyle(.borderedProminent)
                Button("Полное HP") {
                    state.playerHP = state.maxHP
                    if state.isDead { state.isDead = false }
                    SFX.success()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(width: 280)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.25), lineWidth: 1))
        .shadow(radius: 12)
    }
}

// MARK: - Main shooter view

struct ShooterView: View {
    var cheatsUnlocked: Bool
    var autoShowCheats: Bool

    @StateObject private var state: ShooterState
    @State private var appeared = false
    @State private var dragStartYaw: Float = 0
    @State private var dragStartPitch: Float = 0
    @State private var isDragging = false

    init(cheatsUnlocked: Bool = false, autoShowCheats: Bool = false) {
        self.cheatsUnlocked = cheatsUnlocked
        self.autoShowCheats = autoShowCheats
        _state = StateObject(wrappedValue: ShooterState(cheatsUnlocked: cheatsUnlocked, showCheatMenu: autoShowCheats))
    }

    var body: some View {
        ZStack {
            ShooterSceneView(state: state)
                .ignoresSafeArea()
                .gesture(lookGesture)

            // Damage flash
            if state.damageFlash {
                Color.red.opacity(0.35).ignoresSafeArea().allowsHitTesting(false)
            }

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
            .allowsHitTesting(false)

            // HUD & controls
            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Счёт: \(state.score)")
                            .font(.headline.bold()).foregroundColor(.white)
                        HStack(spacing: 6) {
                            Text("HP")
                                .font(.caption.bold()).foregroundColor(.white.opacity(0.9))
                            ProgressView(value: Double(max(0, state.playerHP)), total: Double(state.maxHP))
                                .tint(state.playerHP > 30 ? .green : .red)
                                .frame(width: 120)
                            Text("\(state.playerHP)")
                                .font(.caption.monospacedDigit()).foregroundColor(.white)
                        }
                        if state.godMode || state.freezeBots || state.rapidFire {
                            Text("Читы активны")
                                .font(.caption2).foregroundColor(.yellow)
                        }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Text("Тяни для обзора • Боты стреляют")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                            .padding(8)
                            .background(.ultraThinMaterial, in: Capsule())
                        if state.cheatsUnlocked {
                            Button {
                                state.showCheatMenu.toggle()
                                SFX.tap()
                            } label: {
                                Label("Читы", systemImage: "wand.and.stars")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)

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
                    } label: {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(gradient: Gradient(colors: [Color.red, Color.orange]), startPoint: .top, endPoint: .bottom))
                                .frame(width: 78, height: 78)
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
                .padding(.bottom, 16)
            }

            // Cheat menu overlay
            if state.showCheatMenu && state.cheatsUnlocked {
                VStack {
                    HStack {
                        Spacer()
                        CheatMenuView(state: state)
                            .padding(.top, 60)
                            .padding(.trailing, 14)
                    }
                    Spacer()
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Death overlay
            if state.isDead {
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 14) {
                    Text("Вас убили")
                        .font(.largeTitle.bold()).foregroundColor(.white)
                    Text("Счёт: \(state.score)")
                        .font(.title3).foregroundColor(.white.opacity(0.9))
                    Button("Рестарт") {
                        state.restartRequested = true
                        SFX.click()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .opacity(appeared ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: state.showCheatMenu)
        .onAppear { withAnimation(.easeOut(duration: 0.35)) { appeared = true } }
    }

    private var lookGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                // ignore drags starting on bottom control area roughly? hard to know; keep simple
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
