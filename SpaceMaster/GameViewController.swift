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
import GameKit

public enum GameState {
    case title
    case introduction
    case playing
    case paused
    case credits
    case highScores
    case leaderboard
    case gameOver
}

class GameViewController: UIViewController, SCNSceneRendererDelegate, SCNPhysicsContactDelegate, GKGameCenterControllerDelegate {

    var gameState: GameState = .title
    
    var scene : SCNScene?
    var limits : CGRect = CGRect.zero
    var motion : CMMotionManager = CMMotionManager()

    var hud : SKScene?
    var marcadorAsteroides : SKLabelNode?
    var marcadorBest : SKLabelNode?
    var marcadorLevel : SKLabelNode?
    var damageFlashOverlay : SKShapeNode?
    var lastDisplayedLevel : Int = 1
    var bestScore: Int = UserDefaults.standard.integer(forKey: "BEST_SCORE")
    var bestScoreAtRunStart: Int = UserDefaults.standard.integer(forKey: "BEST_SCORE")
    var gameCenterEnabled: Bool = false

    // IDs oficiales/preparados para Game Center.
    // El leaderboard ya fue creado en App Store Connect con este ID exacto.
    let gameCenterLeaderboardID = "com.carlsalf.spacemasterie.highscore"

    // Estos IDs deben crearse igual en App Store Connect > Game Center > Logros.
    let achievementFirstHitID = "com.carlsalf.spacemasterie.achievement.first_hit"
    let achievement10HitsID = "com.carlsalf.spacemasterie.achievement.10_hits"
    let achievement25HitsID = "com.carlsalf.spacemasterie.achievement.25_hits"
    let achievement50HitsID = "com.carlsalf.spacemasterie.achievement.50_hits"
    let achievement100HitsID = "com.carlsalf.spacemasterie.achievement.100_hits"
    let achievementLevel3ID = "com.carlsalf.spacemasterie.achievement.level_3"
    let achievementLevel5ID = "com.carlsalf.spacemasterie.achievement.level_5"
    let achievementLevel8ID = "com.carlsalf.spacemasterie.achievement.level_8"
    let achievementNewRecordID = "com.carlsalf.spacemasterie.achievement.new_record"
    let achievementSurvivorID = "com.carlsalf.spacemasterie.achievement.survivor"

    var titleGroup : SCNNode?
    var creditsGroup : SCNNode?
    var highScoresGroup : SCNNode?
    var leaderboardGroup : SCNNode?
    var gameOverGroup : SCNNode?
    var gameOverResultsText : SCNText?
    var pauseButtonLabel : SKLabelNode?
    var pauseOverlayLabel : SKLabelNode?
    var pauseOverlayBackground : SKShapeNode?
    var lastScore: Int = UserDefaults.standard.integer(forKey: "LAST_SCORE")
    var maxLevelReached: Int = UserDefaults.standard.integer(forKey: "MAX_LEVEL_REACHED")
    var localHighScores: [Int] = []
    
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

        loadLocalHighScores()
        authenticateGameCenter()

        let scnView = self.view as! SCNView

        let scene = SCNScene(named: "art.scnassets/ship.scn")!
        self.scene = scene
        
        scene.background.contents = UIColor.black
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
        setupAppLifecycleObservers()

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
    

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc func handleAppWillResignActive() {
        pauseGame(showOverlay: true)
    }

    @objc func handleAppDidEnterBackground() {
        pauseGame(showOverlay: true)
    }

    // MARK: - Local Hi-Scores

    func loadLocalHighScores() {
        let storedScores = UserDefaults.standard.array(forKey: "SPACEMASTER_TOP_5_SCORES") as? [Int] ?? []

        // Fuente única y coherente para la pantalla HI-SCORES:
        // se integran el TOP local, el BEST histórico y el LAST si existían
        // antes de la nueva estructura TOP 5. Así evitamos que BEST quede
        // fuera del ranking local, que fue la inconsistencia detectada.
        var mergedScores = storedScores
        if bestScore > 0 { mergedScores.append(bestScore) }
        if lastScore > 0 { mergedScores.append(lastScore) }

        localHighScores = Array(Set(mergedScores.filter { $0 > 0 }).sorted(by: >).prefix(5))
        saveLocalHighScores()

        if let realBest = localHighScores.first, realBest > bestScore {
            bestScore = realBest
            UserDefaults.standard.set(bestScore, forKey: "BEST_SCORE")
        }
    }

    func saveLocalHighScores() {
        UserDefaults.standard.set(localHighScores, forKey: "SPACEMASTER_TOP_5_SCORES")
    }

    func registerLocalHighScore(_ score: Int) {
        guard score > 0 else { return }

        loadLocalHighScores()
        localHighScores.append(score)
        localHighScores = Array(Set(localHighScores.filter { $0 > 0 }).sorted(by: >).prefix(5))
        saveLocalHighScores()

        if score > bestScore {
            bestScore = score
            UserDefaults.standard.set(bestScore, forKey: "BEST_SCORE")
        }
    }

    func formattedLocalHighScores() -> String {
        loadLocalHighScores()

        if localHighScores.isEmpty {
            return "NO SCORES YET"
        }

        return localHighScores.enumerated()
            .map { index, score in
                "\(index + 1). \(score) HITS"
            }
            .joined(separator: "\n")
    }

    // MARK: - Game Center

    func authenticateGameCenter() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            guard let self = self else { return }

            if let viewController = viewController {
                DispatchQueue.main.async {
                    self.present(viewController, animated: true)
                }
                return
            }

            if GKLocalPlayer.local.isAuthenticated {
                self.gameCenterEnabled = true
                print("✅ Game Center conectado")
            } else {
                self.gameCenterEnabled = false
                print("❌ Game Center no autenticado")
                if let error = error {
                    print("Game Center error: \(error.localizedDescription)")
                }
            }
        }
    }

    func reportGameCenterResults(score: Int, level: Int) {
        guard gameCenterEnabled, GKLocalPlayer.local.isAuthenticated else {
            print("Game Center no autenticado: no se envía puntuación online")
            return
        }

        let scoreToReport = max(score, bestScore)

        if #available(iOS 14.0, *) {
            GKLeaderboard.submitScore(
                scoreToReport,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [gameCenterLeaderboardID]
            ) { error in
                if let error = error {
                    print("Game Center leaderboard error: \(error.localizedDescription)")
                } else {
                    print("✅ BEST score enviado a Game Center: \(scoreToReport)")
                }
            }
        } else {
            let scoreReporter = GKScore(leaderboardIdentifier: gameCenterLeaderboardID)
            scoreReporter.value = Int64(scoreToReport)
            GKScore.report([scoreReporter]) { error in
                if let error = error {
                    print("Game Center leaderboard error: \(error.localizedDescription)")
                } else {
                    print("✅ BEST score enviado a Game Center: \(scoreToReport)")
                }
            }
        }

        var achievements: [GKAchievement] = []

        func unlock(_ identifier: String) {
            let achievement = GKAchievement(identifier: identifier)
            achievement.percentComplete = 100.0
            achievement.showsCompletionBanner = true
            achievements.append(achievement)
        }

        if score >= 1 { unlock(achievementFirstHitID) }
        if score >= 10 { unlock(achievement10HitsID) }
        if score >= 25 { unlock(achievement25HitsID) }
        if score >= 50 { unlock(achievement50HitsID) }
        if score >= 100 { unlock(achievement100HitsID) }
        if level >= 3 { unlock(achievementLevel3ID) }
        if level >= 5 { unlock(achievementLevel5ID) }
        if level >= 8 { unlock(achievementLevel8ID) }
        if score > bestScoreAtRunStart && score > 0 { unlock(achievementNewRecordID) }
        if score >= 75 { unlock(achievementSurvivorID) }

        guard achievements.isEmpty == false else { return }

        GKAchievement.report(achievements) { error in
            if let error = error {
                print("Game Center achievements error: \(error.localizedDescription)")
            } else {
                print("✅ Logros enviados a Game Center")
            }
        }
    }

    func showGameCenterDashboard() {
        guard GKLocalPlayer.local.isAuthenticated else {
            authenticateGameCenter()
            return
        }

        let gameCenterVC = GKGameCenterViewController()
        gameCenterVC.gameCenterDelegate = self
        gameCenterVC.viewState = .leaderboards
        gameCenterVC.leaderboardIdentifier = gameCenterLeaderboardID
        present(gameCenterVC, animated: true)
    }

    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
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

        // Reproducción no posicional y estable. Evita crear nodos temporales de audio
        // durante impactos rápidos, que podía provocar crashes de SceneKit/CFRetain.
        scene.rootNode.runAction(SCNAction.playAudio(sound, waitForCompletion: false))
    }


    func playButtonClick() {
        // Efecto de botón seguro. Usa el sonido de disparo a bajo volumen como fallback
        // para evitar depender de un asset adicional antes de la entrega final.
        playSound(soundShot, duration: 0.25)
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
        tapNode.name = "menuTapStart"
        centerPivot(of: tapNode)
        tapNode.position = SCNVector3(0, 2, -20)
        tapNode.scale = SCNVector3(0.42, 0.42, 0.42)
        titleGroup.addChildNode(tapNode)
        
        let playText = SCNText(string: "PLAY", extrusionDepth: 0.7)
        playText.font = UIFont(name: "University", size: 5.2) ?? UIFont.systemFont(ofSize: 5.2, weight: .bold)
        playText.flatness = 0.2
        playText.firstMaterial?.diffuse.contents = UIColor.orange

        let playNode = SCNNode(geometry: playText)
        playNode.name = "menuPlay"
        centerPivot(of: playNode)
        playNode.position = SCNVector3(0, -4.2, -20)
        playNode.scale = SCNVector3(0.42, 0.42, 0.42)
        titleGroup.addChildNode(playNode)

        let highScoreText = SCNText(string: "HI-SCORES", extrusionDepth: 0.7)
        highScoreText.font = UIFont(name: "University", size: 4.6) ?? UIFont.systemFont(ofSize: 4.6, weight: .bold)
        highScoreText.flatness = 0.2
        highScoreText.firstMaterial?.diffuse.contents = UIColor.white

        let highScoreNode = SCNNode(geometry: highScoreText)
        highScoreNode.name = "menuHighScores"
        centerPivot(of: highScoreNode)
        highScoreNode.position = SCNVector3(0, -8.3, -20)
        highScoreNode.scale = SCNVector3(0.40, 0.40, 0.40)
        titleGroup.addChildNode(highScoreNode)

        let leaderboardText = SCNText(string: "LEADERBOARD", extrusionDepth: 0.7)
        leaderboardText.font = UIFont(name: "University", size: 4.1) ?? UIFont.systemFont(ofSize: 4.1, weight: .bold)
        leaderboardText.flatness = 0.2
        leaderboardText.firstMaterial?.diffuse.contents = UIColor.white

        let leaderboardNode = SCNNode(geometry: leaderboardText)
        leaderboardNode.name = "menuLeaderboard"
        centerPivot(of: leaderboardNode)
        leaderboardNode.position = SCNVector3(0, -12.2, -20)
        leaderboardNode.scale = SCNVector3(0.36, 0.36, 0.36)
        titleGroup.addChildNode(leaderboardNode)

        let creditsMenuText = SCNText(string: "CREDITS", extrusionDepth: 0.7)
        creditsMenuText.font = UIFont(name: "University", size: 4.5) ?? UIFont.systemFont(ofSize: 4.5, weight: .bold)
        creditsMenuText.flatness = 0.2
        creditsMenuText.firstMaterial?.diffuse.contents = UIColor.white

        let creditsMenuNode = SCNNode(geometry: creditsMenuText)
        creditsMenuNode.name = "menuCredits"
        centerPivot(of: creditsMenuNode)
        creditsMenuNode.position = SCNVector3(0, -16.0, -20)
        creditsMenuNode.scale = SCNVector3(0.38, 0.38, 0.38)
        titleGroup.addChildNode(creditsMenuNode)

        scene.rootNode.addChildNode(titleGroup)
        self.titleGroup = titleGroup

        let creditsGroup = SCNNode()
        creditsGroup.name = "creditsGroup"
        creditsGroup.isHidden = true

        let creditsTitle = SCNText(string: "CREDITS", extrusionDepth: 0.7)
        creditsTitle.font = UIFont(name: "University", size: 6.2) ?? UIFont.systemFont(ofSize: 6.2, weight: .bold)
        creditsTitle.flatness = 0.2
        creditsTitle.firstMaterial?.diffuse.contents = UIColor.orange

        let creditsTitleNode = SCNNode(geometry: creditsTitle)
        centerPivot(of: creditsTitleNode)
        creditsTitleNode.position = SCNVector3(0, 9, -26)
        creditsTitleNode.scale = SCNVector3(0.34, 0.34, 0.34)
        creditsGroup.addChildNode(creditsTitleNode)

        let creditLines: [(String, Float, UIColor, CGFloat, Float)] = [
            ("SPACE MASTER", 4.2, UIColor.white, 4.2, 0.30),
            ("DEVELOPED BY", 1.6, UIColor.white, 3.7, 0.28),
            ("CARLOS ALFREDO", -0.2, UIColor.white, 3.7, 0.28),
            ("CALLAGUA LLAQUE", -2.0, UIColor.white, 3.7, 0.28),
            ("UNIVERSIDAD DE ALICANTE", -4.7, UIColor.white, 3.4, 0.25),
            ("SCENEKIT SWIFT IOS", -6.3, UIColor.white, 3.4, 0.25)
        ]

        for (text, y, color, fontSize, scaleValue) in creditLines {
            let lineText = SCNText(string: text, extrusionDepth: 0.55)
            lineText.font = UIFont(name: "University", size: fontSize) ?? UIFont.systemFont(ofSize: fontSize, weight: .bold)
            lineText.flatness = 0.2
            lineText.firstMaterial?.diffuse.contents = color

            let lineNode = SCNNode(geometry: lineText)
            centerPivot(of: lineNode)
            lineNode.position = SCNVector3(0, y, -22)
            lineNode.scale = SCNVector3(scaleValue, scaleValue, scaleValue)
            creditsGroup.addChildNode(lineNode)
        }

        let creditsBackText = SCNText(string: "TAP TO MENU", extrusionDepth: 0.7)
        creditsBackText.font = UIFont(name: "University", size: 4.0) ?? UIFont.systemFont(ofSize: 4.0, weight: .bold)
        creditsBackText.flatness = 0.2
        creditsBackText.firstMaterial?.diffuse.contents = UIColor.orange

        let creditsBackNode = SCNNode(geometry: creditsBackText)
        creditsBackNode.name = "backToMenu"
        centerPivot(of: creditsBackNode)
        creditsBackNode.position = SCNVector3(0, -9.0, -20)
        creditsBackNode.scale = SCNVector3(0.32, 0.32, 0.32)
        creditsGroup.addChildNode(creditsBackNode)

        scene.rootNode.addChildNode(creditsGroup)
        self.creditsGroup = creditsGroup

        let highScoresGroup = SCNNode()
        highScoresGroup.name = "highScoresGroup"
        highScoresGroup.isHidden = true

        let highScoresText = SCNText(string: "HI-SCORES", extrusionDepth: 0.7)
        highScoresText.font = UIFont(name: "University", size: 6.4) ?? UIFont.systemFont(ofSize: 6.4, weight: .bold)
        highScoresText.flatness = 0.2
        highScoresText.firstMaterial?.diffuse.contents = UIColor.orange

        let highScoresNode = SCNNode(geometry: highScoresText)
        centerPivot(of: highScoresNode)
        highScoresNode.position = SCNVector3(0, 9, -26)
        highScoresNode.scale = SCNVector3(0.38, 0.38, 0.38)
        highScoresGroup.addChildNode(highScoresNode)

        let highScoresInfo = SCNText(string: "", extrusionDepth: 0.7)
        highScoresInfo.font = UIFont(name: "University", size: 4.8) ?? UIFont.systemFont(ofSize: 4.8, weight: .bold)
        highScoresInfo.flatness = 0.2
        highScoresInfo.firstMaterial?.diffuse.contents = UIColor.white

        let highScoresInfoNode = SCNNode(geometry: highScoresInfo)
        highScoresInfoNode.name = "highScoresInfoNode"
        centerPivot(of: highScoresInfoNode)
        highScoresInfoNode.position = SCNVector3(0, 0.8, -22)
        highScoresInfoNode.scale = SCNVector3(0.30, 0.30, 0.30)
        highScoresGroup.addChildNode(highScoresInfoNode)

        let highScoresBack = SCNText(string: "TAP TO MENU", extrusionDepth: 0.7)
        highScoresBack.font = UIFont(name: "University", size: 4.0) ?? UIFont.systemFont(ofSize: 4.0, weight: .bold)
        highScoresBack.flatness = 0.2
        highScoresBack.firstMaterial?.diffuse.contents = UIColor.orange

        let highScoresBackNode = SCNNode(geometry: highScoresBack)
        highScoresBackNode.name = "backToMenu"
        centerPivot(of: highScoresBackNode)
        highScoresBackNode.position = SCNVector3(0, -8.8, -20)
        highScoresBackNode.scale = SCNVector3(0.32, 0.32, 0.32)
        highScoresGroup.addChildNode(highScoresBackNode)

        scene.rootNode.addChildNode(highScoresGroup)
        self.highScoresGroup = highScoresGroup


        let leaderboardGroup = SCNNode()
        leaderboardGroup.name = "leaderboardGroup"
        leaderboardGroup.isHidden = true

        let leaderboardTitle = SCNText(string: "LEADERBOARD", extrusionDepth: 0.7)
        leaderboardTitle.font = UIFont(name: "University", size: 5.8) ?? UIFont.systemFont(ofSize: 5.8, weight: .bold)
        leaderboardTitle.flatness = 0.2
        leaderboardTitle.firstMaterial?.diffuse.contents = UIColor.orange

        let leaderboardTitleNode = SCNNode(geometry: leaderboardTitle)
        centerPivot(of: leaderboardTitleNode)
        leaderboardTitleNode.position = SCNVector3(0, 9, -26)
        leaderboardTitleNode.scale = SCNVector3(0.34, 0.34, 0.34)
        leaderboardGroup.addChildNode(leaderboardTitleNode)

        let leaderboardLines: [(String, Float, UIColor, CGFloat, Float)] = [
            ("GAME CENTER", 3.2, UIColor.white, 4.1, 0.30),
            ("ONLINE RANKING", 1.3, UIColor.white, 3.7, 0.28),
            ("HIGH SCORE", -1.3, UIColor.white, 3.7, 0.28),
            ("SPACEMASTER", -3.0, UIColor.white, 3.7, 0.28),
            ("TAP TO OPEN", -5.5, UIColor.white, 3.4, 0.25)
        ]

        for (text, y, color, fontSize, scaleValue) in leaderboardLines {
            let lineText = SCNText(string: text, extrusionDepth: 0.55)
            lineText.font = UIFont(name: "University", size: fontSize) ?? UIFont.systemFont(ofSize: fontSize, weight: .bold)
            lineText.flatness = 0.2
            lineText.firstMaterial?.diffuse.contents = color

            let lineNode = SCNNode(geometry: lineText)
            centerPivot(of: lineNode)
            lineNode.position = SCNVector3(0, y, -22)
            lineNode.scale = SCNVector3(scaleValue, scaleValue, scaleValue)
            leaderboardGroup.addChildNode(lineNode)
        }

        let leaderboardBackText = SCNText(string: "TAP TO MENU", extrusionDepth: 0.7)
        leaderboardBackText.font = UIFont(name: "University", size: 4.0) ?? UIFont.systemFont(ofSize: 4.0, weight: .bold)
        leaderboardBackText.flatness = 0.2
        leaderboardBackText.firstMaterial?.diffuse.contents = UIColor.orange

        let leaderboardBackNode = SCNNode(geometry: leaderboardBackText)
        leaderboardBackNode.name = "backToMenu"
        centerPivot(of: leaderboardBackNode)
        leaderboardBackNode.position = SCNVector3(0, -8.8, -20)
        leaderboardBackNode.scale = SCNVector3(0.32, 0.32, 0.32)
        leaderboardGroup.addChildNode(leaderboardBackNode)

        scene.rootNode.addChildNode(leaderboardGroup)
        self.leaderboardGroup = leaderboardGroup

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

        // HUD final estable: HITS izquierda, BEST derecha y LVL centrado debajo.
        // Se mantiene compacto para evitar solapes con scores de 2 y 3 dígitos.
        let safeTop = view.safeAreaInsets.top
        let topY = view.bounds.height - max(86, safeTop + 60)
        let levelY = topY - 66
        let sideMargin: CGFloat = 34

        let scoreLabel = SKLabelNode(fontNamed: "University")
        scoreLabel.text = "0 HITS"
        scoreLabel.fontSize = 30
        scoreLabel.fontColor = UIColor.orange
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.position = CGPoint(x: sideMargin, y: topY)
        scoreLabel.zPosition = 100

        hud.addChild(scoreLabel)
        self.marcadorAsteroides = scoreLabel

        let bestLabel = SKLabelNode(fontNamed: "University")
        bestLabel.text = "BEST \(bestScore)"
        bestLabel.fontSize = 30
        bestLabel.fontColor = UIColor.white
        bestLabel.horizontalAlignmentMode = .right
        bestLabel.verticalAlignmentMode = .center
        bestLabel.position = CGPoint(x: view.bounds.width - sideMargin, y: topY)
        bestLabel.zPosition = 100

        hud.addChild(bestLabel)
        self.marcadorBest = bestLabel

        let levelLabel = SKLabelNode(fontNamed: "University")
        levelLabel.text = "LVL 1"
        levelLabel.fontSize = 34
        levelLabel.fontColor = UIColor(red: 0.95, green: 0.85, blue: 0.25, alpha: 1.0)
        levelLabel.horizontalAlignmentMode = .center
        levelLabel.verticalAlignmentMode = .center
        levelLabel.position = CGPoint(x: view.bounds.midX, y: levelY)
        levelLabel.zPosition = 100

        hud.addChild(levelLabel)
        self.marcadorLevel = levelLabel

        let damageOverlay = SKShapeNode(rectOf: hud.size)
        damageOverlay.position = CGPoint(x: hud.size.width / 2, y: hud.size.height / 2)
        damageOverlay.fillColor = UIColor(red: 1.0, green: 0.05, blue: 0.0, alpha: 1.0)
        damageOverlay.strokeColor = .clear
        damageOverlay.alpha = 0.0
        damageOverlay.zPosition = 1000
        hud.addChild(damageOverlay)
        self.damageFlashOverlay = damageOverlay

        // Botón de pausa separado del marcador principal para no sobrecargar el HUD.
        // Se sitúa abajo a la izquierda, fuera de HITS/BEST/LVL.
        let safeBottom = view.safeAreaInsets.bottom
        let pauseLabel = SKLabelNode(fontNamed: "University")
        pauseLabel.text = "PAUSE"
        pauseLabel.fontSize = 18
        pauseLabel.fontColor = UIColor.white
        pauseLabel.horizontalAlignmentMode = .left
        pauseLabel.verticalAlignmentMode = .center
        pauseLabel.position = CGPoint(x: sideMargin, y: max(62, safeBottom + 48))
        pauseLabel.zPosition = 1250
        hud.addChild(pauseLabel)
        self.pauseButtonLabel = pauseLabel

        let pauseBackground = SKShapeNode(rectOf: hud.size)
        pauseBackground.position = CGPoint(x: hud.size.width / 2, y: hud.size.height / 2)
        pauseBackground.fillColor = UIColor.black
        pauseBackground.strokeColor = .clear
        pauseBackground.alpha = 0.56
        pauseBackground.zPosition = 1100
        pauseBackground.isHidden = true
        hud.addChild(pauseBackground)
        self.pauseOverlayBackground = pauseBackground

        let pausedLabel = SKLabelNode(fontNamed: "University")
        pausedLabel.text = "PAUSED\nTAP TO RESUME"
        pausedLabel.numberOfLines = 2
        pausedLabel.fontSize = 29
        pausedLabel.fontColor = UIColor.orange
        pausedLabel.horizontalAlignmentMode = .center
        pausedLabel.verticalAlignmentMode = .center
        pausedLabel.position = CGPoint(x: hud.size.width / 2, y: hud.size.height * 0.53)
        pausedLabel.zPosition = 1200
        pausedLabel.isHidden = true
        hud.addChild(pausedLabel)
        self.pauseOverlayLabel = pausedLabel

        view.overlaySKScene = hud
        self.hud = hud
        self.hud?.isHidden = gameState != .playing
        updateScoreHUD()
    }

    func currentLevel() -> Int {
        return min(8, (numAsteroides / 10) + 1)
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

        // Ajuste responsivo: evita que HITS invada BEST en pantalla vertical.
        marcadorAsteroides?.fontSize = numAsteroides >= 100 ? 24 : (numAsteroides >= 10 ? 28 : 30)
        marcadorBest?.fontSize = bestScore >= 100 ? 24 : 30
        marcadorLevel?.fontSize = 34
    }

    func showLevelUpFeedback(level: Int) {
        guard let hud = self.hud, gameState == .playing else { return }

        let label = SKLabelNode(fontNamed: "University")
        label.text = "LEVEL \(level)"
        label.fontSize = 44
        label.fontColor = UIColor(red: 1.0, green: 0.88, blue: 0.18, alpha: 1.0)
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: hud.size.width / 2.0, y: hud.size.height * 0.58)
        label.zPosition = 250
        label.alpha = 0.0
        label.setScale(0.75)

        hud.addChild(label)

        marcadorLevel?.removeAllActions()
        marcadorLevel?.run(SKAction.sequence([
            SKAction.scale(to: 1.16, duration: 0.12),
            SKAction.scale(to: 1.0, duration: 0.16)
        ]))

        label.run(SKAction.sequence([
            SKAction.group([
                SKAction.fadeAlpha(to: 1.0, duration: 0.12),
                SKAction.scale(to: 1.12, duration: 0.18)
            ]),
            SKAction.wait(forDuration: 0.42),
            SKAction.fadeAlpha(to: 0.0, duration: 0.18),
            SKAction.removeFromParent()
        ]))
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
    

    func showDamageFlash() {
        guard let overlay = damageFlashOverlay else { return }

        overlay.removeAllActions()
        overlay.alpha = 0.22

        overlay.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.0, duration: 0.18)
        ]))
    }

    func shakeCamera(intensity: CGFloat, duration: TimeInterval) {
        guard let cameraNode = self.cameraNode else { return }

        cameraNode.removeAction(forKey: "cameraShake")

        let half = duration / 4.0
        let moveLeft = SCNAction.moveBy(x: -intensity, y: 0, z: 0, duration: half)
        let moveRight = SCNAction.moveBy(x: intensity * 2.0, y: 0, z: 0, duration: half)
        let moveBack = SCNAction.moveBy(x: -intensity, y: 0, z: 0, duration: half)
        let settle = SCNAction.wait(duration: half)

        cameraNode.runAction(
            SCNAction.sequence([moveLeft, moveRight, moveBack, settle]),
            forKey: "cameraShake"
        )
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

        let move = SCNAction.move(
            to: SCNVector3(pos.x, 0, 60),
            duration: dynamicDuration
        )

        let rotate = SCNAction.rotate(
            by: 10.0,
            around: randomAxis,
            duration: dynamicDuration
        )
        let group = SCNAction.group([move, rotate])
        let remove = SCNAction.removeFromParentNode()
        
        asteroid.runAction(.sequence([group, remove]))
    }
    
    func shot() {
        // Bloqueo crítico de calidad: si la nave ya fue destruida,
        // no se permite disparar durante la transición hacia Game Over.
        guard gameState == .playing,
              shipDestroyed == false,
              let scene = self.scene,
              let ship = self.ship,
              ship.isHidden == false else { return }

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
        // Si la nave ya explotó, ningún disparo residual debe seguir sumando puntos.
        guard gameState == .playing, shipDestroyed == false else { return }

        guard asteroid.parent != nil,
              bullet.parent != nil,
              asteroid.name == "asteroid",
              bullet.name == "bullet" else { return }

        // Bloqueo inmediato para evitar doble procesamiento en frames consecutivos.
        asteroid.name = "destroyingAsteroid"
        bullet.name = "destroyingBullet"

        let explosionPosition = asteroid.presentation.position
        let previousLevel = currentLevel()

        asteroid.physicsBody = nil
        bullet.physicsBody = nil
        asteroid.removeAllActions()
        bullet.removeAllActions()

        // Primero se eliminan los nodos de juego.
        // La explosión se crea después en una posición independiente,
        // evitando referencias inválidas de SceneKit/CFRetain.
        bullet.removeFromParentNode()
        asteroid.removeFromParentNode()

        numAsteroides += 1
        if numAsteroides > bestScore {
            bestScore = numAsteroides
            UserDefaults.standard.set(bestScore, forKey: "BEST_SCORE")
        }
        updateScoreHUD()

        let newLevel = currentLevel()
        if newLevel > previousLevel {
            lastDisplayedLevel = newLevel
            showLevelUpFeedback(level: newLevel)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self = self, self.gameState == .playing else { return }
            self.showExplosion(at: explosionPosition, isShipExplosion: false)
            self.playSound(self.soundExplosion, at: explosionPosition, duration: 1.0)
        }
    }

    func destroyShip(ship: SCNNode, withAsteroid asteroid: SCNNode) {
        guard gameState == .playing,
              shipDestroyed == false,
              asteroid.parent != nil,
              asteroid.name == "asteroid" else { return }
        shipDestroyed = true

        let crashPosition = ship.presentation.position

        asteroid.name = "destroyingAsteroid"
        asteroid.physicsBody = nil
        asteroid.removeAllActions()
        asteroid.removeFromParentNode()

        showExplosion(at: crashPosition, isShipExplosion: true)
        showDamageFlash()
        shakeCamera(intensity: 1.0, duration: 0.18)
        playSound(soundShipCrash, at: crashPosition, duration: 1.5)

        // Limpieza inmediata de disparos activos: evita que se vean proyectiles residuales
        // o que parezca que la nave todavía puede atacar después de explotar.
        scene?.rootNode.enumerateChildNodes { node, _ in
            if node.name == "bullet" || node.name == "destroyingBullet" {
                node.removeAllActions()
                node.removeFromParentNode()
            }
        }

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


        // Respaldo independiente de SCNAction: si la escena se pausa o una acción queda interrumpida,
        // la pantalla final se muestra igualmente. Esto corrige el caso observado de nave destruida
        // sin transición a Game Over.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) { [weak self] in
            guard let self = self else { return }
            if self.shipDestroyed && self.gameState != .gameOver {
                self.showGameOver()
            }
        }
    }
    func showExplosion(onNode node: SCNNode) {
        showExplosion(at: node.presentation.position, isShipExplosion: node.name == "ship")
    }

    func showExplosion(at position: SCNVector3, isShipExplosion: Bool) {
        guard let scene = self.scene else { return }

        let explosionGroup = SCNNode()
        explosionGroup.name = "explosionNode"
        explosionGroup.position = position
        scene.rootNode.addChildNode(explosionGroup)

        // Explosión estable sin SCNParticleSystem para evitar el crash CFRetain.
        // Se usan nodos independientes: más impacto visual, sin esfera amarilla sólida.
        let sparkCount = isShipExplosion ? 52 : 42
        let sparkRadiusRange: ClosedRange<CGFloat> = isShipExplosion ? 0.075...0.145 : 0.050...0.100
        let spread: Float = isShipExplosion ? 7.0 : 4.8
        let duration: TimeInterval = isShipExplosion ? 0.90 : 0.66

        let colors: [UIColor] = [
            UIColor(red: 1.0, green: 0.90, blue: 0.18, alpha: 1.0),
            UIColor(red: 1.0, green: 0.55, blue: 0.06, alpha: 1.0),
            UIColor(red: 1.0, green: 0.25, blue: 0.02, alpha: 1.0),
            UIColor(red: 1.0, green: 0.98, blue: 0.65, alpha: 1.0)
        ]

        for index in 0..<sparkCount {
            let sparkGeometry = SCNSphere(radius: CGFloat.random(in: sparkRadiusRange))
            sparkGeometry.segmentCount = 6

            let material = SCNMaterial()
            material.diffuse.contents = colors[index % colors.count]
            material.emission.contents = colors[index % colors.count]
            material.lightingModel = .constant
            sparkGeometry.materials = [material]

            let sparkNode = SCNNode(geometry: sparkGeometry)
            sparkNode.name = "explosionSpark"
            sparkNode.position = SCNVector3Zero
            explosionGroup.addChildNode(sparkNode)

            let angle = Float.random(in: 0...(Float.pi * 2.0))
            let vertical = Float.random(in: -1.0...1.0)
            let distance = Float.random(in: spread * 0.20...spread)

            let dx = cos(angle) * distance
            let dy = vertical * distance * 0.38
            let dz = sin(angle) * distance

            let move = SCNAction.moveBy(
                x: CGFloat(dx),
                y: CGFloat(dy),
                z: CGFloat(dz),
                duration: duration
            )
            move.timingMode = .easeOut

            let scale = SCNAction.scale(to: 0.01, duration: duration)
            let fade = SCNAction.fadeOpacity(to: 0.0, duration: duration)
            let remove = SCNAction.removeFromParentNode()

            sparkNode.runAction(.sequence([
                .group([move, scale, fade]),
                remove
            ]))
        }

        // Micro-destello: puntos breves y pequeños para dar fuerza sin volver al bloque amarillo.
        let flashCount = isShipExplosion ? 10 : 7
        for _ in 0..<flashCount {
            let flashGeometry = SCNSphere(radius: isShipExplosion ? 0.12 : 0.085)
            flashGeometry.segmentCount = 6

            let flashMaterial = SCNMaterial()
            flashMaterial.diffuse.contents = UIColor(red: 1.0, green: 0.88, blue: 0.12, alpha: 0.9)
            flashMaterial.emission.contents = UIColor(red: 1.0, green: 0.70, blue: 0.04, alpha: 1.0)
            flashMaterial.lightingModel = .constant
            flashGeometry.materials = [flashMaterial]

            let flashNode = SCNNode(geometry: flashGeometry)
            flashNode.name = "explosionFlash"
            flashNode.position = SCNVector3(
                Float.random(in: -0.35...0.35),
                Float.random(in: -0.14...0.14),
                Float.random(in: -0.35...0.35)
            )
            explosionGroup.addChildNode(flashNode)

            flashNode.runAction(.sequence([
                .group([
                    .scale(to: isShipExplosion ? 1.65 : 1.18, duration: 0.07),
                    .fadeOpacity(to: 0.0, duration: 0.13)
                ]),
                .removeFromParentNode()
            ]))
        }

        // Humo suave: un poco más visible, pero sin tapar la escena.
        let smokeCount = isShipExplosion ? 8 : 4
        for _ in 0..<smokeCount {
            let smokeGeometry = SCNSphere(radius: CGFloat.random(in: isShipExplosion ? 0.10...0.18 : 0.065...0.115))
            smokeGeometry.segmentCount = 8

            let smokeMaterial = SCNMaterial()
            smokeMaterial.diffuse.contents = UIColor(white: 0.34, alpha: 0.18)
            smokeMaterial.emission.contents = UIColor(white: 0.13, alpha: 0.08)
            smokeMaterial.lightingModel = .constant
            smokeGeometry.materials = [smokeMaterial]

            let smokeNode = SCNNode(geometry: smokeGeometry)
            smokeNode.name = "explosionSmoke"
            smokeNode.opacity = isShipExplosion ? 0.36 : 0.24
            smokeNode.position = SCNVector3Zero
            explosionGroup.addChildNode(smokeNode)

            let dx = CGFloat.random(in: -1.05...1.05)
            let dy = CGFloat.random(in: -0.30...0.30)
            let dz = CGFloat.random(in: -1.05...1.05)

            smokeNode.runAction(.sequence([
                .group([
                    .moveBy(x: dx, y: dy, z: dz, duration: isShipExplosion ? 0.90 : 0.62),
                    .scale(to: isShipExplosion ? 2.1 : 1.45, duration: isShipExplosion ? 0.90 : 0.62),
                    .fadeOpacity(to: 0.0, duration: isShipExplosion ? 0.90 : 0.62)
                ]),
                .removeFromParentNode()
            ]))
        }

        let light = SCNLight()
        light.type = .omni
        light.color = UIColor.orange
        light.intensity = isShipExplosion ? 1300 : 560

        let lightNode = SCNNode()
        lightNode.name = "explosionLight"
        lightNode.light = light
        lightNode.position = position
        scene.rootNode.addChildNode(lightNode)

        let initialIntensity = light.intensity
        let lightDuration: TimeInterval = isShipExplosion ? 0.26 : 0.20
        let fadeLight = SCNAction.customAction(duration: lightDuration) { node, elapsedTime in
            let progress = CGFloat(elapsedTime / lightDuration)
            node.light?.intensity = initialIntensity * max(0.0, 1.0 - progress)
        }

        lightNode.runAction(.sequence([
            fadeLight,
            .removeFromParentNode()
        ]))

        explosionGroup.runAction(.sequence([
            .wait(duration: isShipExplosion ? 1.10 : 0.76),
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
              collisionProcessing == false,
              let rootNode = scene?.rootNode,
              let ship = self.ship else { return }

        let bullets = rootNode.childNodes.filter { $0.name == "bullet" }
        let asteroids = rootNode.childNodes.filter { $0.name == "asteroid" }

        for bullet in bullets {
            for asteroid in asteroids {
                guard bullet.parent != nil,
                      asteroid.parent != nil,
                      bullet.name == "bullet",
                      asteroid.name == "asteroid" else { continue }

                if distanceBetween(bullet, asteroid) < 8.0 {
                    collisionProcessing = true

                    DispatchQueue.main.async { [weak self, weak asteroid, weak bullet] in
                        guard let self = self else { return }
                        defer { self.collisionProcessing = false }

                        guard let asteroid = asteroid,
                              let bullet = bullet else { return }

                        self.destroyAsteroid(asteroid: asteroid, withBullet: bullet)
                    }
                    return
                }
            }
        }

        for asteroid in asteroids {
            guard asteroid.parent != nil,
                  asteroid.name == "asteroid",
                  shipDestroyed == false else { continue }

            if distanceBetween(ship, asteroid) < 8.0 {
                collisionProcessing = true

                DispatchQueue.main.async { [weak self, weak ship, weak asteroid] in
                    guard let self = self else { return }
                    defer { self.collisionProcessing = false }

                    guard let ship = ship,
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
        collisionProcessing = false
        previousUpdateTime = nil
        timeToSpawn = currentSpawnInterval()
        
        clearGameNodes()
        
        scene?.rootNode.isPaused = false

        titleGroup?.isHidden = false
        creditsGroup?.isHidden = true
        highScoresGroup?.isHidden = true
        leaderboardGroup?.isHidden = true
        gameOverGroup?.isHidden = true
        hud?.isHidden = true
        pauseOverlayLabel?.isHidden = true
        pauseOverlayBackground?.isHidden = true
        damageFlashOverlay?.removeAllActions()
        damageFlashOverlay?.alpha = 0.0
        pauseButtonLabel?.text = "PAUSE"
        
        ship?.removeAllActions()
        ship?.isHidden = true
        ship?.position = SCNVector3(0, 0, 20)
        ship?.eulerAngles = SCNVector3Zero
        
        playBackgroundMusic()
    }
    
    func showGameOver() {
        // Debe ejecutarse siempre tras la destrucción de la nave, aunque haya acciones pausadas
        // o el juego haya entrado en un estado intermedio. Esto evita quedarse sin pantalla final.
        guard gameState != .gameOver else { return }

        let finalLevel = currentLevel()
        let finalScore = numAsteroides
        let newRecord = finalScore > bestScoreAtRunStart && finalScore > 0

        gameState = .gameOver
        scene?.rootNode.isPaused = false
        stopBackgroundMusic()

        lastScore = finalScore
        maxLevelReached = max(maxLevelReached, finalLevel)
        registerLocalHighScore(finalScore)
        UserDefaults.standard.set(lastScore, forKey: "LAST_SCORE")
        UserDefaults.standard.set(maxLevelReached, forKey: "MAX_LEVEL_REACHED")

        pauseOverlayLabel?.isHidden = true
        pauseOverlayBackground?.isHidden = true
        damageFlashOverlay?.removeAllActions()
        damageFlashOverlay?.alpha = 0.0
        pauseButtonLabel?.text = "PAUSE"
        hud?.isHidden = true
        titleGroup?.isHidden = true
        creditsGroup?.isHidden = true
        highScoresGroup?.isHidden = true
        gameOverGroup?.isHidden = false

        var resultText = "SCORE: \(finalScore)\nBEST: \(bestScore)\nLEVEL: \(finalLevel)"
        if newRecord {
            resultText += "\nNEW RECORD!"
        }
        gameOverResultsText?.string = resultText
        if let resultsNode = gameOverGroup?.childNode(withName: "resultsNode", recursively: false) {
            centerPivot(of: resultsNode)
        }

        reportGameCenterResults(score: finalScore, level: finalLevel)

        clearGameNodes(keepExplosions: true)

        gameOverGroup?.position = SCNVector3(0, 0, 0)
        gameOverGroup?.scale = SCNVector3(1, 1, 1)
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
        creditsGroup?.isHidden = true
        highScoresGroup?.isHidden = true
        leaderboardGroup?.isHidden = true
        gameOverGroup?.isHidden = true
        hud?.isHidden = false
        ship?.isHidden = false
        
        numAsteroides = 0
        bestScoreAtRunStart = bestScore
        lastDisplayedLevel = 1
        updateScoreHUD()
        
        ship?.removeAllActions()
        ship?.opacity = 1.0
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
        
        guard gameState == .playing, shipDestroyed == false, let ship = self.ship else { return }
        
        timeToSpawn -= deltaTime
        if timeToSpawn <= 0 {
            let asteroidMargin: Float = 7.0
            let randomX = Float.getRandom(
                from: Float(limits.minX) + asteroidMargin,
                to: Float(limits.minX + limits.width) - asteroidMargin
            )
            let spawnPos = SCNVector3(randomX, 0, -120)
            spawnAsteroid(pos: spawnPos)
            timeToSpawn = currentSpawnInterval()
        }

        let nextX = ship.position.x + velocity * 120.0 * Float(deltaTime)
        let shipScreenMargin: Float = 10.0
        let minX = Float(limits.minX) + shipScreenMargin
        let maxX = Float(limits.minX + limits.width) - shipScreenMargin

        ship.position.x = max(minX, min(maxX, nextX))
        ship.eulerAngles = SCNVector3(0, 0, -velocity * 0.75)
        
        checkManualCollisions()
    }
    
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        // Las colisiones se gestionan manualmente en checkManualCollisions().
        // Se deja vacío para evitar dobles eventos sobre los mismos nodos.
    }
    

    func showHighScores() {
        gameState = .highScores
        clearGameNodes()
        hud?.isHidden = true
        titleGroup?.isHidden = true
        creditsGroup?.isHidden = true
        leaderboardGroup?.isHidden = true
        gameOverGroup?.isHidden = true
        highScoresGroup?.isHidden = false
        ship?.isHidden = true

        if let infoNode = highScoresGroup?.childNode(withName: "highScoresInfoNode", recursively: true),
           let infoText = infoNode.geometry as? SCNText {
            infoText.string = "TOP 5 LOCAL\n\(formattedLocalHighScores())\n\nBEST: \(bestScore)\nLAST: \(lastScore)\nMAX LVL: \(maxLevelReached)"
            centerPivot(of: infoNode)
        }
    }

    func showLeaderboard() {
        gameState = .leaderboard
        clearGameNodes()
        hud?.isHidden = true
        titleGroup?.isHidden = true
        highScoresGroup?.isHidden = true
        creditsGroup?.isHidden = true
        gameOverGroup?.isHidden = true
        leaderboardGroup?.isHidden = false
        ship?.isHidden = true
    }

    func showCredits() {
        gameState = .credits
        clearGameNodes()
        hud?.isHidden = true
        titleGroup?.isHidden = true
        highScoresGroup?.isHidden = true
        leaderboardGroup?.isHidden = true
        gameOverGroup?.isHidden = true
        creditsGroup?.isHidden = false
        ship?.isHidden = true
    }

    func pauseGame(showOverlay: Bool) {
        guard gameState == .playing else { return }

        gameState = .paused
        scene?.rootNode.isPaused = true
        pauseButtonLabel?.text = "RESUME"
        pauseButtonLabel?.fontColor = UIColor.orange
        pauseOverlayBackground?.isHidden = showOverlay == false
        pauseOverlayLabel?.isHidden = showOverlay == false
        backgroundMusicPlayer?.pause()
    }

    func resumeGame() {
        guard gameState == .paused else { return }

        scene?.rootNode.isPaused = false
        pauseOverlayBackground?.isHidden = true
        pauseOverlayLabel?.isHidden = true
        pauseButtonLabel?.text = "PAUSE"
        pauseButtonLabel?.fontColor = UIColor.white
        // No se reinicia la música de introducción al reanudar una partida.
        // El gameplay se mantiene sin música de menú para evitar mezcla de audio.
        previousUpdateTime = nil
        gameState = .playing
    }

    func isPauseButtonTap(_ location: CGPoint, in view: UIView) -> Bool {
        // UIKit mide desde arriba; el botón está abajo a la izquierda en el overlay SpriteKit.
        let bottomTapArea = max(96, view.safeAreaInsets.bottom + 92)
        return location.x <= 150 && location.y >= view.bounds.height - bottomTapArea
    }

    func projectedCenter(of nodeName: String, in group: SCNNode?) -> CGPoint? {
        guard let scnView = self.view as? SCNView,
              let group = group,
              group.isHidden == false,
              let node = group.childNode(withName: nodeName, recursively: true) else {
            return nil
        }

        let projected = scnView.projectPoint(node.presentation.worldPosition)
        return CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
    }

    func isProjectedNodeTap(
        _ nodeName: String,
        in group: SCNNode?,
        location: CGPoint,
        view: UIView,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat
    ) -> Bool {
        guard let scnView = view as? SCNView,
              let group = group,
              group.isHidden == false,
              let node = group.childNode(withName: nodeName, recursively: true) else {
            return false
        }

        let projected = scnView.projectPoint(node.presentation.worldPosition)
        let center = CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))

        let tapArea = CGRect(
            x: center.x - horizontalPadding,
            y: center.y - verticalPadding,
            width: horizontalPadding * 2.0,
            height: verticalPadding * 2.0
        )

        return tapArea.contains(location)
    }

    func handleTitleMenuTap(_ location: CGPoint, in view: UIView) {
        // Detección precisa y estable del menú principal:
        // 1) Hit-test real sobre las letras 3D.
        // 2) Fallback por cercanía al centro visual de cada opción.
        // Esto corrige el problema de tocar HI-SCORES y que se inicie PLAY.

        if let scnView = view as? SCNView {
            let hits = scnView.hitTest(location, options: [
                SCNHitTestOption.boundingBoxOnly: true,
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue
            ])

            for hit in hits {
                var node: SCNNode? = hit.node

                while let current = node {
                    switch current.name {
                    case "menuTapStart", "menuPlay":
                        playButtonClick()
                        startGame()
                        return

                    case "menuHighScores":
                        playButtonClick()
                        showHighScores()
                        return

                    case "menuLeaderboard":
                        playButtonClick()
                        showLeaderboard()
                        return

                    case "menuCredits":
                        playButtonClick()
                        showCredits()
                        return

                    default:
                        node = current.parent
                    }
                }
            }
        }

        // Fallback: elegir la opción más cercana al dedo.
        // Los márgenes son horizontales, pero la decisión se hace por la distancia vertical,
        // evitando que la caja de PLAY invada HI-SCORES.
        let options: [(node: String, action: String, maxX: CGFloat, maxY: CGFloat)] = [
            ("menuPlay", "play", 135, 30),
            ("menuHighScores", "scores", 180, 34),
            ("menuLeaderboard", "leaderboard", 210, 34),
            ("menuCredits", "credits", 155, 34)
        ]

        var selected: (action: String, distance: CGFloat)?

        for option in options {
            guard let center = projectedCenter(of: option.node, in: titleGroup) else { continue }

            let dx = abs(location.x - center.x)
            let dy = abs(location.y - center.y)

            guard dx <= option.maxX, dy <= option.maxY else { continue }

            let distance = dy + (dx * 0.18)
            if selected == nil || distance < selected!.distance {
                selected = (option.action, distance)
            }
        }

        if let selected = selected {
            playButtonClick()

            switch selected.action {
            case "play":
                startGame()

            case "scores":
                showHighScores()

            case "leaderboard":
                showLeaderboard()

            case "credits":
                showCredits()

            default:
                break
            }

            return
        }

        // TAP TO START queda separado para no tragarse las opciones del menú.
        if isProjectedNodeTap("menuTapStart", in: titleGroup, location: location, view: view, horizontalPadding: 175, verticalPadding: 34) {
            playButtonClick()
            startGame()
        }
    }

    func isRestartButtonTap(_ location: CGPoint, in view: UIView) -> Bool {
        guard let scnView = view as? SCNView,
              let restartNode = gameOverGroup?.childNode(withName: "restartNode", recursively: true),
              restartNode.isHidden == false,
              gameOverGroup?.isHidden == false else {
            return false
        }

        let projectedPosition = scnView.projectPoint(restartNode.presentation.worldPosition)
        let restartCenter = CGPoint(x: CGFloat(projectedPosition.x), y: CGFloat(projectedPosition.y))

        let restartTapArea = CGRect(
            x: restartCenter.x - 120,
            y: restartCenter.y - 28,
            width: 240,
            height: 56
        )

        return restartTapArea.contains(location)
    }

    @objc
    func handleTap(_ gestureRecognize: UIGestureRecognizer) {
        let location = gestureRecognize.location(in: self.view)

        if gameState == .playing {
            // Si la nave ya explotó, se ignora cualquier toque hasta que aparezca Game Over.
            guard shipDestroyed == false else { return }

            if isPauseButtonTap(location, in: self.view) {
                pauseGame(showOverlay: true)
            } else {
                shot()
            }
            return
        }

        if gameState == .paused {
            resumeGame()
            return
        }

        if gameState == .title {
            handleTitleMenuTap(location, in: self.view)
            return
        }

        if gameState == .credits {
            if isProjectedNodeTap("backToMenu", in: creditsGroup, location: location, view: self.view, horizontalPadding: 145, verticalPadding: 34) {
                playButtonClick()
                showTitle()
            }
            return
        }

        if gameState == .highScores {
            if isProjectedNodeTap("backToMenu", in: highScoresGroup, location: location, view: self.view, horizontalPadding: 145, verticalPadding: 34) {
                playButtonClick()
                showTitle()
            }
            return
        }

        if gameState == .leaderboard {
            if isProjectedNodeTap("backToMenu", in: leaderboardGroup, location: location, view: self.view, horizontalPadding: 145, verticalPadding: 34) {
                playButtonClick()
                showTitle()
            } else {
                playButtonClick()
                showGameCenterDashboard()
            }
            return
        }

        if gameState == .gameOver {
            if isRestartButtonTap(location, in: self.view) {
                playButtonClick()
                startGame()
            }
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
