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
import AVFoundation

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
    var marcadorBest : SKLabelNode?
    var marcadorLevel : SKLabelNode?
    var bestScore: Int = UserDefaults.standard.integer(forKey: "BEST_SCORE")

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

    var backgroundMusicPlayer: AVAudioPlayer?
    var soundExplosion : SCNAudioSource?
    var soundShipCrash : SCNAudioSource?
    var soundShot : SCNAudioSource?

    var numAsteroides : Int = 0
    var velocity : Float = 0.0
    var shipDestroyed : Bool = false
    var collisionProcessing : Bool = false

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

        self.explosion = SCNParticleSystem(named: "Explode.scnp", inDirectory: "ParticleSystem")
            ?? SCNParticleSystem(named: "ParticleSystem/Explode.scnp", inDirectory: nil)

        if self.explosion == nil {
            print("Error: Explode.scnp particle system not found")
        }

        setupTitleAndGameOver()
        setupLights(inScene: scene)
        setupAsteroids(forView: scnView)
        setupAudioSession()
        setupAudio()
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
    
    func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Error setting audio session: \(error)")
        }
    }
    
    func setupAudio() {
        if let url = Bundle.main.url(forResource: "rolemusic_step_to_space", withExtension: "mp3") {
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = -1
                player.volume = 0.25
                player.prepareToPlay()
                self.backgroundMusicPlayer = player
            } catch {
                print("Error loading background music: \(error)")
            }
        } else {
            print("Error: background music file not found")
        }
        
        if let explosionSound = SCNAudioSource(fileNamed: "bomb.wav") {
            explosionSound.volume = 1.0
            explosionSound.isPositional = false
            explosionSound.load()
            self.soundExplosion = explosionSound
        } else {
            print("Error: explosion sound file not found")
        }
        
        if let shipCrashSound = SCNAudioSource(fileNamed: "bomb.wav") {
            shipCrashSound.volume = 1.8
            shipCrashSound.isPositional = false
            shipCrashSound.load()
            self.soundShipCrash = shipCrashSound
        } else {
            print("Error: ship crash sound file not found")
        }
        
        if let shotSound = SCNAudioSource(fileNamed: "bomb.wav") {
            shotSound.volume = 0.18
            shotSound.isPositional = false
            shotSound.load()
            self.soundShot = shotSound
        } else {
            print("Error: shot sound file not found")
        }
    }
    
    func playBackgroundMusic() {
        guard let player = self.backgroundMusicPlayer else { return }
        
        if !player.isPlaying {
            player.currentTime = 0
            player.play()
        }
    }
    
    func stopBackgroundMusic() {
        guard let player = self.backgroundMusicPlayer else { return }
        
        if player.isPlaying {
            player.stop()
            player.currentTime = 0
        }
    }
    
    func playSound(_ sound: SCNAudioSource?, at position: SCNVector3? = nil, duration: TimeInterval = 1.0) {
        guard let scene = self.scene, let sound = sound else { return }
        
        let audioNode = SCNNode()
        audioNode.name = "audioNode"
        audioNode.position = position ?? SCNVector3Zero
        
        scene.rootNode.addChildNode(audioNode)
        audioNode.runAction(.playAudio(sound, waitForCompletion: false))
        audioNode.runAction(.sequence([.wait(duration: duration), .removeFromParentNode()]))
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
        
        let restartText = SCNText(string: "TAP TO RESTART", extrusionDepth: 1.0)
        restartText.font = UIFont(name: "University", size: 4) ?? UIFont.systemFont(ofSize: 4, weight: .bold)
        restartText.flatness = 0.2
        restartText.firstMaterial?.diffuse.contents = UIColor.orange
        
        let restartNode = SCNNode(geometry: restartText)
        restartNode.name = "restartNode"
        centerPivot(of: restartNode)
        restartNode.position = SCNVector3(0, -5, -20)
        restartNode.scale = SCNVector3(0.30, 0.30, 0.30)
        gameOverGroup.addChildNode(restartNode)
        
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

        // HUD final optimizado para iPhone vertical:
        // HITS izquierda, BEST derecha y LVL centrado en segunda línea.
        // Se reduce ligeramente el tamaño para evitar solapes con puntuaciones de 2 dígitos.
        let topY = view.bounds.height - 105
        let levelY = view.bounds.height - 165
        let horizontalMargin: CGFloat = 36

        let scoreLabel = SKLabelNode(fontNamed: "University")
        scoreLabel.text = "0 HITS"
        scoreLabel.fontSize = 32
        scoreLabel.fontColor = UIColor.orange
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.position = CGPoint(x: horizontalMargin, y: topY)
        scoreLabel.zPosition = 100

        hud.addChild(scoreLabel)
        self.marcadorAsteroides = scoreLabel

        let bestLabel = SKLabelNode(fontNamed: "University")
        bestLabel.text = "BEST \(bestScore)"
        bestLabel.fontSize = 32
        bestLabel.fontColor = UIColor.white
        bestLabel.horizontalAlignmentMode = .right
        bestLabel.verticalAlignmentMode = .center
        bestLabel.position = CGPoint(x: view.bounds.width - horizontalMargin, y: topY)
        bestLabel.zPosition = 100

        hud.addChild(bestLabel)
        self.marcadorBest = bestLabel

        let levelLabel = SKLabelNode(fontNamed: "University")
        levelLabel.text = "LVL 1"
        levelLabel.fontSize = 30
        levelLabel.fontColor = UIColor(red: 0.95, green: 0.85, blue: 0.25, alpha: 1.0)
        levelLabel.horizontalAlignmentMode = .center
        levelLabel.verticalAlignmentMode = .center
        levelLabel.position = CGPoint(x: view.bounds.midX, y: levelY)
        levelLabel.zPosition = 100

        hud.addChild(levelLabel)
        self.marcadorLevel = levelLabel

        view.overlaySKScene = hud

        self.hud = hud
        self.hud?.isHidden = gameState != .playing
        updateScoreHUD()
    }

    func currentLevel() -> Int {
        return min(5, (numAsteroides / 10) + 1)
    }

    func currentAsteroidDuration() -> TimeInterval {
        let level = Double(currentLevel())
        let scoreFactor = Double(numAsteroides) * 0.035
        return max(1.55, 5.0 - scoreFactor - ((level - 1.0) * 0.25))
    }

    func currentSpawnInterval() -> TimeInterval {
        let level = Double(currentLevel())
        return max(0.34, Double(spawnInterval) - ((level - 1.0) * 0.055))
    }

    func updateScoreHUD() {
        marcadorAsteroides?.text = "\(numAsteroides) HITS"
        marcadorBest?.text = "BEST \(bestScore)"
        marcadorLevel?.text = "LVL \(currentLevel())"
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

        let dynamicDuration = currentAsteroidDuration()
        let move = SCNAction.move(to: SCNVector3(pos.x, 0, 60), duration: dynamicDuration)
        let rotate = SCNAction.rotate(by: 10.0 + CGFloat(currentLevel()), around: randomAxis, duration: dynamicDuration)
        let group = SCNAction.group([move, rotate])
        let remove = SCNAction.removeFromParentNode()

        asteroid.runAction(.sequence([group, remove]))
    }
    
    func shot() {
        guard gameState == .playing, let scene = self.scene, let ship = self.ship else { return }
        
        playSound(soundShot, at: ship.presentation.position, duration: 0.5)
        
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
        guard asteroid.parent != nil,
              bullet.parent != nil,
              asteroid.name == "asteroid",
              bullet.name == "bullet" else { return }

        asteroid.name = "destroyingAsteroid"
        bullet.name = "destroyingBullet"

        let explosionPosition = asteroid.presentation.position

        asteroid.physicsBody = nil
        bullet.physicsBody = nil
        asteroid.removeAllActions()
        bullet.removeAllActions()

        bullet.removeFromParentNode()
        asteroid.removeFromParentNode()

        numAsteroides += 1
        if numAsteroides > bestScore {
            bestScore = numAsteroides
            UserDefaults.standard.set(bestScore, forKey: "BEST_SCORE")
        }
        updateScoreHUD()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self = self, self.gameState == .playing else { return }
            self.showArcadeExplosion(at: explosionPosition, isShipExplosion: false)
            self.playSound(self.soundExplosion, at: explosionPosition, duration: 0.8)
        }
    }
    
    func destroyShip(ship: SCNNode, withAsteroid asteroid: SCNNode) {
        guard gameState == .playing,
              shipDestroyed == false,
              asteroid.parent != nil else { return }

        shipDestroyed = true

        let crashPosition = ship.presentation.position

        asteroid.physicsBody = nil
        asteroid.removeAllActions()
        asteroid.removeFromParentNode()

        showArcadeExplosion(at: crashPosition, isShipExplosion: true)
        playSound(soundShipCrash, at: crashPosition, duration: 1.5)

        ship.removeAllActions()

        let shakeLeft = SCNAction.moveBy(x: -1.2, y: 0, z: 0, duration: 0.06)
        let shakeRight = SCNAction.moveBy(x: 2.4, y: 0, z: 0, duration: 0.06)
        let shakeBack = SCNAction.moveBy(x: -1.2, y: 0, z: 0, duration: 0.06)
        let hideShip = SCNAction.run { node in
            node.isHidden = true
        }
        let waitExplosion = SCNAction.wait(duration: 1.25)
        let finish = SCNAction.run { [weak self] _ in
            self?.showGameOver()
        }

        ship.runAction(.sequence([
            shakeLeft,
            shakeRight,
            shakeBack,
            hideShip,
            waitExplosion,
            finish
        ]))
    }
    func showExplosion(onNode node: SCNNode) {
        showArcadeExplosion(at: node.presentation.position, isShipExplosion: false)
    }

    func showArcadeExplosion(at position: SCNVector3, isShipExplosion: Bool) {
        guard let scene = self.scene else { return }

        // Stable arcade-style explosion implemented with independent SceneKit nodes.
        // We avoid SCNParticleSystem here because it previously caused CFRetain crashes on device.
        let particleCount = isShipExplosion ? 82 : 24
        let distanceRange: ClosedRange<Float> = isShipExplosion ? -5.4...5.4 : -2.2...2.2
        let duration: TimeInterval = isShipExplosion ? 0.90 : 0.42
        let zRange: ClosedRange<Float> = isShipExplosion ? -1.8...1.8 : -1.2...1.2

        for _ in 0..<particleCount {
            let radius = isShipExplosion
                ? CGFloat.random(in: 0.10...0.24)
                : CGFloat.random(in: 0.07...0.12)

            let particle = SCNNode(geometry: SCNSphere(radius: radius))
            particle.name = "explosionNode"
            particle.position = position

            let colors: [UIColor] = [
                UIColor(red: 1.0, green: 0.82, blue: 0.18, alpha: 1.0),
                UIColor.orange,
                UIColor(red: 1.0, green: 0.28, blue: 0.05, alpha: 1.0),
                UIColor(red: 1.0, green: 0.12, blue: 0.02, alpha: 1.0),
                UIColor.white
            ]

            let material = SCNMaterial()
            material.diffuse.contents = colors.randomElement()
            material.emission.contents = isShipExplosion ? UIColor.orange : UIColor(red: 1.0, green: 0.55, blue: 0.05, alpha: 1.0)
            material.lightingModel = .constant
            particle.geometry?.materials = [material]

            scene.rootNode.addChildNode(particle)

            let x = Float.random(in: distanceRange)
            let y = Float.random(in: distanceRange)
            let z = Float.random(in: zRange)

            let move = SCNAction.moveBy(
                x: CGFloat(x),
                y: CGFloat(y),
                z: CGFloat(z),
                duration: duration
            )
            let fade = SCNAction.fadeOut(duration: duration)
            let scale = SCNAction.scale(to: 0.02, duration: duration)
            let group = SCNAction.group([move, fade, scale])
            let remove = SCNAction.removeFromParentNode()

            particle.runAction(.sequence([group, remove]))
        }

        if isShipExplosion {
            // Short central flash: small enough to avoid the old "yellow block" problem,
            // but visible enough to make the ship crash feel like the main event.
            let flash = SCNNode(geometry: SCNSphere(radius: 0.75))
            flash.name = "explosionFlash"
            flash.position = position

            let flashMaterial = SCNMaterial()
            flashMaterial.diffuse.contents = UIColor(red: 1.0, green: 0.65, blue: 0.05, alpha: 0.55)
            flashMaterial.emission.contents = UIColor(red: 1.0, green: 0.35, blue: 0.02, alpha: 1.0)
            flashMaterial.transparency = 0.55
            flashMaterial.lightingModel = .constant
            flash.geometry?.materials = [flashMaterial]

            scene.rootNode.addChildNode(flash)

            flash.runAction(.sequence([
                .group([
                    .scale(to: 1.65, duration: 0.16),
                    .fadeOut(duration: 0.22)
                ]),
                .removeFromParentNode()
            ]))

            // Secondary embers: slower fragments that remain briefly after the main flash.
            for _ in 0..<22 {
                let ember = SCNNode(geometry: SCNSphere(radius: CGFloat.random(in: 0.05...0.10)))
                ember.name = "explosionNode"
                ember.position = position

                let emberMaterial = SCNMaterial()
                emberMaterial.diffuse.contents = UIColor(red: 0.95, green: 0.30, blue: 0.08, alpha: 1.0)
                emberMaterial.emission.contents = UIColor(red: 0.9, green: 0.22, blue: 0.04, alpha: 1.0)
                emberMaterial.lightingModel = .constant
                ember.geometry?.materials = [emberMaterial]

                scene.rootNode.addChildNode(ember)

                let move = SCNAction.moveBy(
                    x: CGFloat(Float.random(in: -3.6...3.6)),
                    y: CGFloat(Float.random(in: -3.6...3.6)),
                    z: CGFloat(Float.random(in: -1.2...1.2)),
                    duration: 1.05
                )
                let fade = SCNAction.fadeOut(duration: 1.05)
                ember.runAction(.sequence([
                    .group([move, fade, .scale(to: 0.01, duration: 1.05)]),
                    .removeFromParentNode()
                ]))
            }
        }

        let light = SCNLight()
        light.type = .omni
        light.color = UIColor.orange
        light.intensity = isShipExplosion ? 4200 : 900

        let lightNode = SCNNode()
        lightNode.name = "explosionLight"
        lightNode.light = light
        lightNode.position = position
        scene.rootNode.addChildNode(lightNode)

        let lightDuration: TimeInterval = isShipExplosion ? 0.48 : 0.25
        let initialIntensity: CGFloat = isShipExplosion ? 4200 : 900

        let fadeLight = SCNAction.customAction(duration: lightDuration) { node, elapsedTime in
            let progress = CGFloat(elapsedTime / lightDuration)
            node.light?.intensity = initialIntensity * max(0.0, 1.0 - progress)
        }

        lightNode.runAction(.sequence([
            fadeLight,
            .removeFromParentNode()
        ]))
    }

    func clearGameNodes(keepExplosions: Bool = false) {
        guard let rootNode = scene?.rootNode else { return }

        for node in rootNode.childNodes {
            if node.name == "asteroid" ||
                node.name == "bullet" ||
                node.name == "audioNode" ||
                (!keepExplosions && node.name == "explosionNode") ||
                (!keepExplosions && node.name == "explosionLight") ||
                (!keepExplosions && node.name == "explosionFlash") {
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
                guard bullet.parent != nil, asteroid.parent != nil else { continue }

                if distanceBetween(bullet, asteroid) < 8.0 {
                    DispatchQueue.main.async { [weak self, weak asteroid, weak bullet] in
                        guard let self = self,
                              let asteroid = asteroid,
                              let bullet = bullet else { return }
                        self.destroyAsteroid(asteroid: asteroid, withBullet: bullet)
                    }
                    return
                }
            }
        }

        for asteroid in asteroids {
            guard asteroid.parent != nil, shipDestroyed == false else { continue }

            if distanceBetween(ship, asteroid) < 8.0 {
                DispatchQueue.main.async { [weak self, weak ship, weak asteroid] in
                    guard let self = self,
                          let ship = ship,
                          let asteroid = asteroid else { return }
                    self.destroyShip(ship: ship, withAsteroid: asteroid)
                }
                return
            }
        }
    }
        
    func showTitle() {
        gameState = .title
        shipDestroyed = false
        previousUpdateTime = nil
        timeToSpawn = currentSpawnInterval()
        
        clearGameNodes()
        
        titleGroup?.isHidden = false
        gameOverGroup?.isHidden = true
        hud?.isHidden = true
        
        ship?.removeAllActions()
        ship?.isHidden = true
        ship?.position = SCNVector3(0, 0, 20)
        ship?.eulerAngles = SCNVector3Zero
        
        playBackgroundMusic()
    }
    
    func showGameOver() {
        guard gameState == .playing || gameState == .introduction else { return }

        gameState = .gameOver
        stopBackgroundMusic()

        hud?.isHidden = true
        gameOverGroup?.isHidden = false

        let newRecord = numAsteroides >= bestScore && numAsteroides > 0
        var resultText = "SCORE: \(numAsteroides)\nBEST: \(bestScore)\nLEVEL: \(currentLevel())"
        if newRecord {
            resultText += "\nNEW RECORD!"
        }

        gameOverResultsText?.string = resultText
        if let resultsNode = gameOverGroup?.childNode(withName: "resultsNode", recursively: false) {
            centerPivot(of: resultsNode)
        }

        clearGameNodes(keepExplosions: true)

        gameOverGroup?.position = SCNVector3(0, 0, 0)
        gameOverGroup?.opacity = 1.0
        gameOverGroup?.removeAllActions()

        let wait = SCNAction.wait(duration: 0.15)
        let pulseUp = SCNAction.scale(to: 1.05, duration: 0.25)
        let pulseDown = SCNAction.scale(to: 1.0, duration: 0.25)
        let pulse = SCNAction.repeatForever(.sequence([pulseUp, pulseDown]))

        gameOverGroup?.runAction(.sequence([wait, pulse]))
    }
    
    func startGame() {
        gameState = .introduction
        shipDestroyed = false
        collisionProcessing = false
        previousUpdateTime = nil
        timeToSpawn = 1.2
        
        stopBackgroundMusic()
        clearGameNodes()
        
        titleGroup?.isHidden = true
        gameOverGroup?.isHidden = true
        hud?.isHidden = false
        ship?.isHidden = false
        
        numAsteroides = 0
        updateScoreHUD()
        
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
            timeToSpawn = currentSpawnInterval()
        }

        let nextX = ship.position.x + velocity * 120.0 * Float(deltaTime)
        let minX = Float(limits.minX)
        let maxX = Float(limits.minX + limits.width)
        
        ship.position.x = max(minX, min(maxX, nextX))
        ship.eulerAngles = SCNVector3(0, 0, -velocity * 0.75)
        
        checkManualCollisions()
    }
    
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        // Las colisiones se procesan manualmente en checkManualCollisions().
        // Mantener este delegado sin lógica evita dobles eventos y protege la estabilidad del prototipo.
    }
    
    @objc
    func handleTap(_ gestureRecognize: UIGestureRecognizer) {
        if gameState == .playing {
            shot()
            return
        }
        
        if gameState == .title {
            startGame()
            return
        }
        
        if gameState == .gameOver {
            startGame()
            return
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
