//
//  GameViewController.swift
//  Asteroids
//
//  Created by Miguel Angel Lozano Ortega on 02/01/2020.
//  Copyright © 2020 Miguel Angel Lozano Ortega. All rights reserved.
//

import UIKit
import QuartzCore
import SceneKit
import SpriteKit
import CoreMotion

public enum GameState {
    case title
    case introduction
    case playing
    case gameOver
}

class GameViewController: UIViewController, SCNSceneRendererDelegate, SCNPhysicsContactDelegate {

    var gameState: GameState = .title
    
    var scene : SCNScene?
    var limits : CGRect = CGRect.zero
    var motion : CMMotionManager = CMMotionManager()

    var hud : SKScene?
    var marcadorAsteroides : SKLabelNode?

    var titleGroup : SCNNode?
    var gameOverGroup : SCNNode?
    var gameOverResultsText : SCNText?
    
    var cameraNode : SCNNode?
    var cameraEulerAngle : SCNVector3?

    let categoryMaskShip = 0b001
    let categoryMaskShot = 0b010
    let categoryMaskAsteroid = 0b100

    var ship : SCNNode?
    var asteroidModel : SCNNode?
    var explosion : SCNParticleSystem?

    var soundExplosion : SCNAudioSource?

    var numAsteroides : Int = 0
    var velocity : Float = 0.0
    var shipDestroyed : Bool = false

    let spawnInterval : Float = 0.65
    var timeToSpawn : TimeInterval = 1.0
    var previousUpdateTime : TimeInterval?

    override func viewDidLoad() {
        super.viewDidLoad()

        let scnView = self.view as! SCNView

        let scene = SCNScene(named: "art.scnassets/ship.scn")!
        self.scene = scene
        
        scene.background.contents = UIImage(named: "galaxy.png")
        scene.lightingEnvironment.contents = UIImage(named: "galaxy.png")
        scene.lightingEnvironment.intensity = 1.1
              
        self.cameraNode = scene.rootNode.childNode(withName: "camera", recursively: true)
        if self.cameraNode == nil {
            let camera = SCNCamera()
            camera.zFar = 200
            
            let node = SCNNode()
            node.name = "camera"
            node.camera = camera
            node.position = SCNVector3(0, 55, 35)
            node.eulerAngles = SCNVector3(-Float.pi / 3.2, 0, 0)
            scene.rootNode.addChildNode(node)
            self.cameraNode = node
        }
        self.cameraEulerAngle = self.cameraNode?.eulerAngles

        self.ship = scene.rootNode.childNode(withName: "ship", recursively: true)
        if self.ship == nil {
            self.ship = scene.rootNode.childNodes.first
            self.ship?.name = "ship"
        }

        if let ship = self.ship {
            let shipShape = SCNPhysicsShape(
                geometry: SCNSphere(radius: 4.0),
                options: nil
            )
            ship.physicsBody = SCNPhysicsBody(type: .kinematic, shape: shipShape)
            ship.physicsBody?.categoryBitMask = categoryMaskShip
            ship.physicsBody?.contactTestBitMask = categoryMaskAsteroid
            ship.physicsBody?.collisionBitMask = 0
        }

        self.explosion = SCNParticleSystem(named: "ParticleSystem/Explode.scnp", inDirectory: nil)

        setupTitleAndGameOver()
        setupLights(inScene: scene)
        setupAsteroids(forView: scnView)
        setupAudio(inScene: scene)
        setupView(scnView, withScene: scene)
        startTapRecognition(inView: scnView)
        startMotionUpdates()

        scene.physicsWorld.contactDelegate = self
        
        showTitle()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        let scnView = self.view as! SCNView
        
        setupLimits(forView: scnView)
        setupHUD(inView: scnView)
        showTitle()
    }
    
    func setupLights(inScene scene: SCNScene) {
        let omniLight = SCNLight()
        omniLight.type = .omni
        omniLight.color = UIColor.white
        omniLight.intensity = 1800
        
        let omniNode = SCNNode()
        omniNode.name = "omni"
        omniNode.light = omniLight
        omniNode.position = SCNVector3(0, 10, 20)
        scene.rootNode.addChildNode(omniNode)
        
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = UIColor(white: 0.45, alpha: 1.0)
        ambientLight.intensity = 900
        
        let ambientNode = SCNNode()
        ambientNode.name = "ambient"
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)
    }
    
    func setupTitleAndGameOver() {
        guard let scene = self.scene else { return }
        
        let titleGroup = SCNNode()
        titleGroup.name = "titleGroup"
        
        let titleText = SCNText(string: "SPACE MASTER", extrusionDepth: 1.0)
        titleText.font = UIFont(name: "University", size: 8) ?? UIFont.boldSystemFont(ofSize: 8)
        titleText.flatness = 0.2
        titleText.firstMaterial?.diffuse.contents = UIColor.orange
        
        let titleNode = SCNNode(geometry: titleText)
        centerPivot(of: titleNode)
        titleNode.position = SCNVector3(0, 10, -30)
        titleNode.scale = SCNVector3(0.38, 0.38, 0.38)
        titleGroup.addChildNode(titleNode)
        
        let tapText = SCNText(string: "TAP TO START", extrusionDepth: 1.0)
        tapText.font = UIFont(name: "University", size: 5) ?? UIFont.systemFont(ofSize: 5, weight: .bold)
        tapText.flatness = 0.2
        tapText.firstMaterial?.diffuse.contents = UIColor.white
        
        let tapNode = SCNNode(geometry: tapText)
        centerPivot(of: tapNode)
        tapNode.position = SCNVector3(0, 2, -20)
        tapNode.scale = SCNVector3(0.42, 0.42, 0.42)
        titleGroup.addChildNode(tapNode)
        
        scene.rootNode.addChildNode(titleGroup)
        self.titleGroup = titleGroup
        
        let gameOverGroup = SCNNode()
        gameOverGroup.name = "gameOverGroup"
        gameOverGroup.isHidden = true
        
        let gameOverText = SCNText(string: "GAME OVER", extrusionDepth: 1.0)
        gameOverText.font = UIFont(name: "University", size: 8) ?? UIFont.boldSystemFont(ofSize: 8)
        gameOverText.flatness = 0.2
        gameOverText.firstMaterial?.diffuse.contents = UIColor.red
        
        let gameOverNode = SCNNode(geometry: gameOverText)
        centerPivot(of: gameOverNode)
        gameOverNode.position = SCNVector3(0, 10, -30)
        gameOverNode.scale = SCNVector3(0.42, 0.42, 0.42)
        gameOverGroup.addChildNode(gameOverNode)
        
        let resultsText = SCNText(string: "", extrusionDepth: 1.0)
        resultsText.font = UIFont(name: "University", size: 5) ?? UIFont.systemFont(ofSize: 5, weight: .bold)
        resultsText.flatness = 0.2
        resultsText.firstMaterial?.diffuse.contents = UIColor.white
        self.gameOverResultsText = resultsText
        
        let resultsNode = SCNNode(geometry: resultsText)
        resultsNode.name = "resultsNode"
        centerPivot(of: resultsNode)
        resultsNode.position = SCNVector3(0, 2, -20)
        resultsNode.scale = SCNVector3(0.30, 0.30, 0.30)
        gameOverGroup.addChildNode(resultsNode)
        
        scene.rootNode.addChildNode(gameOverGroup)
        self.gameOverGroup = gameOverGroup
    }
    
    func centerPivot(of node: SCNNode) {
        let (minVec, maxVec) = node.boundingBox
        let centerX = (minVec.x + maxVec.x) / 2.0
        let centerY = (minVec.y + maxVec.y) / 2.0
        let centerZ = (minVec.z + maxVec.z) / 2.0
        node.pivot = SCNMatrix4MakeTranslation(centerX, centerY, centerZ)
    }
    
    func setupAudio(inScene scene: SCNScene) {
        if let music = SCNAudioSource(fileNamed: "rolemusic_step_to_space.mp3") {
            music.loops = true
            music.volume = 0.1
            music.isPositional = false
            music.shouldStream = true
            music.load()
            scene.rootNode.runAction(SCNAction.playAudio(music, waitForCompletion: false))
        }
        
        if let sound = SCNAudioSource(fileNamed: "bomb.wav") {
            sound.volume = 10.0
            sound.isPositional = true
            sound.load()
            self.soundExplosion = sound
        }
    }
    
    func setupAsteroids(forView view: SCNView) {
        guard let rockScene = SCNScene(named: "art.scnassets/rock.scn") else { return }
        
        if let asteroid = rockScene.rootNode.childNode(withName: "asteroid", recursively: true) {
            self.asteroidModel = asteroid
        } else {
            self.asteroidModel = rockScene.rootNode.childNodes.first
        }
        
        self.asteroidModel?.name = "asteroid"
        
        if let asteroidModel = self.asteroidModel {
            view.prepare([asteroidModel], completionHandler: nil)
        }
    }
        
    func setupView(_ view: SCNView, withScene scene: SCNScene) {
        view.scene = scene
        view.allowsCameraControl = false
        view.showsStatistics = true
        view.backgroundColor = UIColor.black
        
        if let cameraNode = self.cameraNode {
            view.pointOfView = cameraNode
        }
        
        view.delegate = self
        view.isPlaying = true
    }

    func setupLimits(forView view: SCNView) {
        self.limits = CGRect(x: -22, y: -120, width: 44, height: 180)
    }
    
    func setupHUD(inView view: SCNView) {
        let hud = SKScene(size: view.bounds.size)
        hud.scaleMode = .resizeFill
        hud.backgroundColor = .clear
        
        let label = SKLabelNode(fontNamed: "University")
        label.text = "0 HITS"
        label.fontSize = 44
        label.fontColor = UIColor.orange
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: view.bounds.midX, y: view.bounds.height - 80)
        label.zPosition = 100
        
        hud.addChild(label)
        view.overlaySKScene = hud
        
        self.marcadorAsteroides = label
        self.hud = hud
        self.hud?.isHidden = gameState != .playing
    }

    func startTapRecognition(inView view: SCNView) {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tap)
    }
    
    func startMotionUpdates() {
        guard self.motion.isDeviceMotionAvailable else { return }
        
        self.motion.deviceMotionUpdateInterval = 1.0 / 60.0
        self.motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self = self, let deviceMotion = data else { return }
            
            self.velocity = Float(deviceMotion.attitude.roll)
            
            if let cameraNode = self.cameraNode, let original = self.cameraEulerAngle {
                cameraNode.eulerAngles.x = original.x + Float(deviceMotion.attitude.pitch) * 0.18
                cameraNode.eulerAngles.z = original.z + Float(deviceMotion.attitude.roll) * 0.10
            }
        }
    }
    
    func spawnAsteroid(pos: SCNVector3) {
        guard let scene = self.scene, let asteroidModel = self.asteroidModel else { return }
        
        let asteroid = asteroidModel.clone()
        asteroid.name = "asteroid"
        asteroid.position = pos
        
        let randomAxis = SCNVector3.getRandom()
        
        asteroid.physicsBody = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(node: asteroid, options: nil))
        asteroid.physicsBody?.categoryBitMask = categoryMaskAsteroid
        asteroid.physicsBody?.contactTestBitMask = categoryMaskShot | categoryMaskShip
        asteroid.physicsBody?.collisionBitMask = 0
        
        scene.rootNode.addChildNode(asteroid)
        
        let move = SCNAction.move(to: SCNVector3(pos.x, 0, 60), duration: 5.0)
        let rotate = SCNAction.rotate(by: 10.0, around: randomAxis, duration: 5.0)
        let group = SCNAction.group([move, rotate])
        let remove = SCNAction.removeFromParentNode()
        
        asteroid.runAction(.sequence([group, remove]))
    }
    
    func shot() {
        guard gameState == .playing, let scene = self.scene, let ship = self.ship else { return }
        
        let sphere = SCNSphere(radius: 1.0)
        sphere.firstMaterial?.diffuse.contents = UIColor(red: 0.8, green: 0.7, blue: 0.2, alpha: 1.0)
        sphere.firstMaterial?.emission.contents = UIColor(red: 0.8, green: 0.7, blue: 0.2, alpha: 1.0)
        
        let bullet = SCNNode(geometry: sphere)
        bullet.name = "bullet"
        
        let shipPosition = ship.presentation.position
        bullet.position = SCNVector3(shipPosition.x, shipPosition.y + 1.5, shipPosition.z - 5)
        
        scene.rootNode.addChildNode(bullet)
        
        let move = SCNAction.moveBy(x: 0, y: 0, z: -150, duration: 1.0)
        let remove = SCNAction.removeFromParentNode()
        bullet.runAction(.sequence([move, remove]))
        
        bullet.physicsBody = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: sphere, options: nil))
        bullet.physicsBody?.categoryBitMask = categoryMaskShot
        bullet.physicsBody?.contactTestBitMask = categoryMaskAsteroid
        bullet.physicsBody?.collisionBitMask = 0
    }
    
    func destroyAsteroid(asteroid: SCNNode, withBullet bullet: SCNNode) {
        guard gameState == .playing else { return }

        showExplosion(onNode: asteroid)
        
        asteroid.removeFromParentNode()
        bullet.removeFromParentNode()
        
        numAsteroides += 1
        marcadorAsteroides?.text = "\(numAsteroides) HITS"
    }
    
    func destroyShip(ship: SCNNode, withAsteroid asteroid: SCNNode) {
        guard gameState == .playing, shipDestroyed == false else { return }
        shipDestroyed = true

        showExplosion(onNode: ship)

        asteroid.removeFromParentNode()
        
        let moveBack = SCNAction.moveBy(x: 0, y: 0, z: 20, duration: 0.5)
        let rotate = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2.0, z: 0, duration: 0.5)
        let finish = SCNAction.run { [weak self] _ in
            self?.showGameOver()
        }
        ship.runAction(.sequence([.group([moveBack, rotate]), finish]))
    }
    
    func showExplosion(onNode node: SCNNode) {
        if let explosion = self.explosion {
            let explosionNode = SCNNode()
            explosionNode.name = "explosionNode"
            explosionNode.position = node.presentation.position
            explosionNode.addParticleSystem(explosion)
            scene?.rootNode.addChildNode(explosionNode)
            
            let wait = SCNAction.wait(duration: 2.0)
            let remove = SCNAction.removeFromParentNode()
            explosionNode.runAction(.sequence([wait, remove]))
        }
        
        if let soundExplosion = self.soundExplosion {
            let audioNode = SCNNode()
            audioNode.name = "explosionAudioNode"
            audioNode.position = node.presentation.position
            scene?.rootNode.addChildNode(audioNode)
            audioNode.runAction(.playAudio(soundExplosion, waitForCompletion: false))
            audioNode.runAction(.sequence([.wait(duration: 1.0), .removeFromParentNode()]))
        }
    }
    
    func clearGameNodes() {
        guard let rootNode = scene?.rootNode else { return }
        
        for node in rootNode.childNodes {
            if node.name == "asteroid" ||
                node.name == "bullet" ||
                node.name == "explosionNode" ||
                node.name == "explosionAudioNode" {
                node.removeFromParentNode()
            }
        }
    }
    
    func distanceBetween(_ nodeA: SCNNode, _ nodeB: SCNNode) -> Float {
        let a = nodeA.presentation.position
        let b = nodeB.presentation.position
        
        let dx = a.x - b.x
        let dy = a.y - b.y
        let dz = a.z - b.z
        
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    func checkManualCollisions() {
        guard gameState == .playing,
              let rootNode = scene?.rootNode,
              let ship = self.ship else { return }
        
        let bullets = rootNode.childNodes.filter { $0.name == "bullet" }
        let asteroids = rootNode.childNodes.filter { $0.name == "asteroid" }
        
        for bullet in bullets {
            for asteroid in asteroids {
                if bullet.parent != nil && asteroid.parent != nil {
                    if distanceBetween(bullet, asteroid) < 8.0 {
                        destroyAsteroid(asteroid: asteroid, withBullet: bullet)
                        return
                    }
                }
            }
        }
        
        for asteroid in asteroids {
            if asteroid.parent != nil && shipDestroyed == false {
                if distanceBetween(ship, asteroid) < 8.0 {
                    destroyShip(ship: ship, withAsteroid: asteroid)
                    return
                }
            }
        }
    }
        
    func showTitle() {
        gameState = .title
        shipDestroyed = false
        previousUpdateTime = nil
        timeToSpawn = TimeInterval(spawnInterval)
        
        clearGameNodes()
        
        titleGroup?.isHidden = false
        gameOverGroup?.isHidden = true
        hud?.isHidden = true
        
        ship?.removeAllActions()
        ship?.isHidden = true
        ship?.position = SCNVector3(0, 0, 20)
        ship?.eulerAngles = SCNVector3Zero
    }
    
    func showGameOver() {
        guard gameState == .playing || gameState == .introduction else { return }
        
        gameState = .gameOver
        hud?.isHidden = true
        gameOverGroup?.isHidden = false
        
        gameOverResultsText?.string = "\(numAsteroides) ASTEROIDS DESTROYED"
        if let resultsNode = gameOverGroup?.childNode(withName: "resultsNode", recursively: false) {
            centerPivot(of: resultsNode)
        }
        
        clearGameNodes()
        
        gameOverGroup?.position = SCNVector3(0, 0, 0)
        gameOverGroup?.opacity = 1.0
        gameOverGroup?.removeAllActions()
        
        let move = SCNAction.move(to: SCNVector3(0, 0, -200), duration: 2.0)
        move.timingMode = .easeOut
        let fade = SCNAction.fadeOut(duration: 0.5)
        let backToTitle = SCNAction.run { [weak self] _ in
            self?.showTitle()
        }
        
        gameOverGroup?.runAction(.sequence([move, fade, backToTitle]))
    }
    
    func startGame() {
        gameState = .introduction
        shipDestroyed = false
        previousUpdateTime = nil
        timeToSpawn = 1.2
        
        clearGameNodes()
        
        titleGroup?.isHidden = true
        gameOverGroup?.isHidden = true
        hud?.isHidden = false
        ship?.isHidden = false
        
        numAsteroides = 0
        marcadorAsteroides?.text = "0 HITS"
        
        ship?.removeAllActions()
        ship?.position = SCNVector3(0, 0, 45)
        ship?.eulerAngles = SCNVector3Zero
        
        let move = SCNAction.move(to: SCNVector3(0, 0, 20), duration: 1.0)
        let finish = SCNAction.run { [weak self] _ in
            self?.gameState = .playing
            self?.timeToSpawn = 1.0
            self?.previousUpdateTime = nil
        }
        
        ship?.runAction(.sequence([move, finish]))
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let deltaTime: TimeInterval
        if let previous = previousUpdateTime {
            deltaTime = time - previous
        } else {
            deltaTime = 0
        }
        previousUpdateTime = time
        
        guard gameState == .playing, let ship = self.ship else { return }
        
        timeToSpawn -= deltaTime
        if timeToSpawn <= 0 {
            let randomX = Float.getRandom(from: Float(limits.minX), to: Float(limits.minX + limits.width))
            let spawnPos = SCNVector3(randomX, 0, -120)
            spawnAsteroid(pos: spawnPos)
            timeToSpawn = TimeInterval(spawnInterval)
        }

        let nextX = ship.position.x + velocity * 120.0 * Float(deltaTime)
        let minX = Float(limits.minX)
        let maxX = Float(limits.minX + limits.width)
        
        ship.position.x = max(minX, min(maxX, nextX))
        ship.eulerAngles = SCNVector3(0, 0, -velocity * 0.75)
        
        checkManualCollisions()
    }
    
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        guard gameState == .playing else { return }
        
        let nodeA = contact.nodeA
        let nodeB = contact.nodeB
        
        let maskA = nodeA.physicsBody?.categoryBitMask ?? 0
        let maskB = nodeB.physicsBody?.categoryBitMask ?? 0
        
        if (maskA == categoryMaskShot && maskB == categoryMaskAsteroid) ||
            (maskA == categoryMaskAsteroid && maskB == categoryMaskShot) {
            
            let bullet = maskA == categoryMaskShot ? nodeA : nodeB
            let asteroid = maskA == categoryMaskAsteroid ? nodeA : nodeB
            
            DispatchQueue.main.async { [weak self] in
                self?.destroyAsteroid(asteroid: asteroid, withBullet: bullet)
            }
            return
        }
        
        if (maskA == categoryMaskShip && maskB == categoryMaskAsteroid) ||
            (maskA == categoryMaskAsteroid && maskB == categoryMaskShip) {
            
            let ship = maskA == categoryMaskShip ? nodeA : nodeB
            let asteroid = maskA == categoryMaskAsteroid ? nodeA : nodeB
            
            DispatchQueue.main.async { [weak self] in
                self?.destroyShip(ship: ship, withAsteroid: asteroid)
            }
        }
    }
    
    @objc
    func handleTap(_ gestureRecognize: UIGestureRecognizer) {
        if gameState == .playing {
            shot()
            return
        }
        
        if gameState == .title {
            startGame()
        }
    }
    
    override var shouldAutorotate: Bool {
        return true
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }
}
