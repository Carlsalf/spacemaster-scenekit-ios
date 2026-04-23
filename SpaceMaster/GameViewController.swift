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

// TODO [D01] Definir enumeración con los estados del juego
public enum GameState {
    case title
    case introduction
    case playing
    case gameOver
}

// TODO [B07] Implementar protocolo SCNSceneRendererDelegate
// TODO [C06] Implementar protocolo SCNPhysicsContactDelegate
class GameViewController: UIViewController, SCNSceneRendererDelegate, SCNPhysicsContactDelegate {

    // TODO [D02] Definir campo `gameState` con el estado actual del juego
    var gameState: GameState = .title
    
    // MARK: - Escena, limites de la pantalla y sistema de control de movimiento
    var scene : SCNScene?
    var limits : CGRect = CGRect.zero
    var motion : CMMotionManager = CMMotionManager()

    // MARK: Elementos del HUD
    var hud : SKScene?
    var marcadorAsteroides : SKLabelNode?

    // MARK: Capas de titulo y gameover
    var titleGroup : SCNNode?
    var gameOverGroup : SCNNode?
    var gameOverResultsText : SCNText?
    
    // MARK: Sistema de camara
    var cameraNode : SCNNode?
    var cameraEulerAngle : SCNVector3?

    // MARK: Layering del sistema de fisicas
    let categoryMaskShip = 0b001
    let categoryMaskShot = 0b010
    let categoryMaskAsteroid = 0b100

    // MARK: Nodos de la nave, asteroides y explosion
    var ship : SCNNode?
    var asteroidModel : SCNNode?
    var explosion : SCNParticleSystem?

    // MARK: Efectos de sonido
    var soundExplosion : SCNAudioSource?

    // MARK: Propiedades del juego
    var numAsteroides : Int = 0
    var velocity : Float = 0.0

    // MARK: Control de tiempos
    let spawnInterval : Float = 0.25
    var timeToSpawn : TimeInterval = 1.0
    var previousUpdateTime : TimeInterval?

    // MARK: - Eventos de inicializacion de la vista
    
    override func viewDidLoad() {
        super.viewDidLoad()

        let scnView = self.view as! SCNView

        // Creamos la escena
        let scene = SCNScene(named: "art.scnassets/ship.scn")!
        self.scene = scene
        
        // Fondo espacial
        scene.background.contents = UIImage(named: "galaxy.png")
        scene.lightingEnvironment.contents = UIImage(named: "galaxy.png")
        scene.lightingEnvironment.intensity = 1.1
              
        // TODO [B03] Obtener el nodo "camara" de la escena, y almacenar su orientación original (eulerAngles)
        self.cameraNode = scene.rootNode.childNode(withName: "camera", recursively: true)
        if self.cameraNode == nil {
            let camera = SCNCamera()
            camera.zFar = 200
            
            let node = SCNNode()
            node.name = "camera"
            node.camera = camera
            node.position = SCNVector3(0, 50, 20)
            node.eulerAngles = SCNVector3(-Float.pi / 4.0, 0, 0)
            scene.rootNode.addChildNode(node)
            self.cameraNode = node
        }
        self.cameraEulerAngle = self.cameraNode?.eulerAngles

        // TODO [B04] Obtener el nodo con la nave "ship" a partir de la escena
        self.ship = scene.rootNode.childNode(withName: "ship", recursively: true)
        if self.ship == nil {
            self.ship = scene.rootNode.childNodes.first
            self.ship?.name = "ship"
        }

        // Física de la nave
        if let ship = self.ship {
            ship.physicsBody = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(node: ship, options: nil))
            ship.physicsBody?.categoryBitMask = categoryMaskShip
            ship.physicsBody?.contactTestBitMask = categoryMaskAsteroid
            ship.physicsBody?.collisionBitMask = 0
        }

        // TODO [C11] Inicializamos efecto de particulas
        self.explosion = SCNParticleSystem(named: "ParticleSystem/Explode.scnp", inDirectory: nil)

        // TODO [D08] Inicializa las referencias a las pantallas de titulo, gameover
        setupTitleAndGameOver()

        // Luces
        setupLights(inScene: scene)
        
        // Inicializa los asteroides
        setupAsteroids(forView: scnView)
        
        // Inicializa el audio
        setupAudio(inScene: scene)
        
        // Configura la vista y pone en marcha el ciclo del juego
        setupView(scnView, withScene: scene)
        
        // Pone en marcha las lecturas de sensores y pantalla tactil
        startTapRecognition(inView: scnView)
        startMotionUpdates()

        // TODO [C07] Asignar esta clase como contactDelegate del mundo físico de la escena.
        scene.physicsWorld.contactDelegate = self
        
        // Muestra la capa de la pantalla de titulo
        showTitle()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        let scnView = self.view as! SCNView
        
        setupLimits(forView: scnView)
        setupHUD(inView: scnView)
    }
    
    // MARK: - Metodos para la inicializacion de componentes
    
    func setupLights(inScene scene: SCNScene) {
        let omniLight = SCNLight()
        omniLight.type = .omni
        omniLight.color = UIColor.white
        omniLight.intensity = 1000
        
        let omniNode = SCNNode()
        omniNode.name = "omni"
        omniNode.light = omniLight
        omniNode.position = SCNVector3(0, 5, 10)
        scene.rootNode.addChildNode(omniNode)
        
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = UIColor(white: 0.35, alpha: 1.0)
        ambientLight.intensity = 400
        
        let ambientNode = SCNNode()
        ambientNode.name = "ambient"
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)
    }
    
    func setupTitleAndGameOver() {
        guard let scene = self.scene else { return }
        
        // Grupo de título
        let titleGroup = SCNNode()
        titleGroup.name = "titleGroup"
        
        let titleText = SCNText(string: "SPACE MASTER", extrusionDepth: 1.0)
        titleText.font = UIFont(name: "University", size: 8) ?? UIFont.boldSystemFont(ofSize: 8)
        titleText.flatness = 0.2
        titleText.firstMaterial?.diffuse.contents = UIColor.orange
        
        let titleNode = SCNNode(geometry: titleText)
        centerPivot(of: titleNode)
        titleNode.position = SCNVector3(0, 14, -30)
        titleNode.scale = SCNVector3(0.6, 0.6, 0.6)
        titleGroup.addChildNode(titleNode)
        
        let tapText = SCNText(string: "TAP TO START", extrusionDepth: 1.0)
        tapText.font = UIFont(name: "University", size: 5) ?? UIFont.systemFont(ofSize: 5, weight: .bold)
        tapText.flatness = 0.2
        tapText.firstMaterial?.diffuse.contents = UIColor.white
        
        let tapNode = SCNNode(geometry: tapText)
        centerPivot(of: tapNode)
        tapNode.position = SCNVector3(0, 5, -20)
        tapNode.scale = SCNVector3(0.5, 0.5, 0.5)
        titleGroup.addChildNode(tapNode)
        
        scene.rootNode.addChildNode(titleGroup)
        self.titleGroup = titleGroup
        
        // Grupo de game over
        let gameOverGroup = SCNNode()
        gameOverGroup.name = "gameOverGroup"
        gameOverGroup.isHidden = true
        
        let gameOverText = SCNText(string: "GAME OVER", extrusionDepth: 1.0)
        gameOverText.font = UIFont(name: "University", size: 8) ?? UIFont.boldSystemFont(ofSize: 8)
        gameOverText.flatness = 0.2
        gameOverText.firstMaterial?.diffuse.contents = UIColor.red
        
        let gameOverNode = SCNNode(geometry: gameOverText)
        centerPivot(of: gameOverNode)
        gameOverNode.position = SCNVector3(0, 12, -30)
        gameOverNode.scale = SCNVector3(0.6, 0.6, 0.6)
        gameOverGroup.addChildNode(gameOverNode)
        
        let resultsText = SCNText(string: "", extrusionDepth: 1.0)
        resultsText.font = UIFont(name: "University", size: 5) ?? UIFont.systemFont(ofSize: 5, weight: .bold)
        resultsText.flatness = 0.2
        resultsText.firstMaterial?.diffuse.contents = UIColor.white
        self.gameOverResultsText = resultsText
        
        let resultsNode = SCNNode(geometry: resultsText)
        centerPivot(of: resultsNode)
        resultsNode.position = SCNVector3(0, 4, -20)
        resultsNode.scale = SCNVector3(0.45, 0.45, 0.45)
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
        // TODO [C15] Reproducir musica de fondo "rolemusic_step_to_space.mp3" en bucle, con volumen 0.1, y desde el nodo raiz de la escena.
        if let music = SCNAudioSource(fileNamed: "Audio/rolemusic_step_to_space.mp3") {
            music.loops = true
            music.volume = 0.1
            music.isPositional = false
            music.shouldStream = true
            music.load()
            scene.rootNode.runAction(SCNAction.playAudio(music, waitForCompletion: false))
        }
        
        // TODO [C16] Precarga el efecto bomb.wav, con volumen 10.0, y asignalo al campo soundExplosion
        if let sound = SCNAudioSource(fileNamed: "Audio/bomb.wav") {
            sound.volume = 10.0
            sound.isPositional = true
            sound.load()
            self.soundExplosion = sound
        }
    }
    
    func setupAsteroids(forView view: SCNView) {
        // TODO [C01] Precarga el modelo de asteroide "asteroid" de rock.scn, asignalo al campo asteroidModel, y preparalo para su visualización en view
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
        
        // TODO [B08] Asignar esta clase como delegado del renderer de la escena, y activar la propiedad `isPlaying` de la vista
        view.delegate = self
        view.isPlaying = true
    }

    func setupLimits(forView view: SCNView) {
        // TODO [B06] Calcular y almacenar en `self.limits` el rectángulo que defina los límites de la zona "jugable" dentro del plano XZ de la escena, donde la nave, disparos y asteroides se puedan mover sin salirse de los límites de la pantalla.
        self.limits = CGRect(x: -25, y: -120, width: 50, height: 160)
    }
    
    func setupHUD(inView view: SCNView) {
        // TODO [C13]
        //  - Crea una SKScene del tamaño de la vista y asignala a la capa overlaySKScene de la vista
        //  - Crea un SKLabel con cadena "0 HITS" con fuente University, de tamaño 36 y color naranja
        //  - Situa la etiqueta en la parte superior de la pantalla, centrada en la horizontal, haciendo que todo el texto quede visible en pantalla
        
        //  - Asigna la etiqueta y la escena a los siguientes campos:
        //     self.marcadorAsteroides = ...
        //     self.hud = ...
        let hud = SKScene(size: view.bounds.size)
        hud.scaleMode = .resizeFill
        hud.backgroundColor = .clear
        
        let label = SKLabelNode(fontNamed: "University")
        label.text = "0 HITS"
        label.fontSize = 36
        label.fontColor = UIColor.orange
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: view.bounds.midX, y: view.bounds.height - 50)
        
        hud.addChild(label)
        view.overlaySKScene = hud
        
        self.marcadorAsteroides = label
        self.hud = hud
    }

    // MARK: - Metodos para la inicializacion de los controles
    
    func startTapRecognition(inView view: SCNView) {
        // TODO [B01] Programar un UITapGestureRecognizer y agregarlo a la vista (view)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tap)
    }
    
    func startMotionUpdates() {
        // TODO [B02] Implementar el control mediante Core Motion
        //  - Comprobar en self.motion is Device Motion esta disponible
        //  - Programar el intervalo de refreso de Device Motion updates en 1.0 / 60.0
        //  - Comenzamos la lectura de Device Motion updates
        //  - Hacemos que el ángulo de giro "roll" sea la velocidad (self.velocity) de nuestra nave
        //  - Orientamos la cámara utilizando pitch (eulerAngles.x) y roll (eurlerAngles.z)
        guard self.motion.isDeviceMotionAvailable else { return }
        
        self.motion.deviceMotionUpdateInterval = 1.0 / 60.0
        self.motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self = self, let deviceMotion = data else { return }
            
            self.velocity = Float(deviceMotion.attitude.roll)
            
            if let cameraNode = self.cameraNode, let original = self.cameraEulerAngle {
                cameraNode.eulerAngles.x = original.x + Float(deviceMotion.attitude.pitch) * 0.25
                cameraNode.eulerAngles.z = original.z + Float(deviceMotion.attitude.roll) * 0.15
            }
        }
    }
    
    // MARK: - Metodos para los eventos del juego
    
    func spawnAsteroid(pos: SCNVector3) {
        guard let scene = self.scene, let asteroidModel = self.asteroidModel else { return }
        
        // TODO [C02] Clonar el asteroide "asteroidModel", y asignar las siguiente propiedades:
        //  - Agregar el nuevo asteroide a la escena (nodo raiz)
        //  - Situarlo en pos
        //  - Hacer que se mueva hasta (pos.x, 0, limits.maxY) en 3 segundos
        //  - Hacer que al mismo tiempo el asteroide rote sobre un eje aleatorio, 10 radianes, en 3 segundos
        //  - Tras llegar a su posicion final, debera ser eliminado de la escena.
        let asteroid = asteroidModel.clone()
        asteroid.name = "asteroid"
        asteroid.position = pos
        
        let randomAxis = SCNVector3.getRandom()
        
        asteroid.physicsBody = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(node: asteroid, options: nil))
        asteroid.physicsBody?.categoryBitMask = categoryMaskAsteroid
        asteroid.physicsBody?.contactTestBitMask = categoryMaskShot | categoryMaskShip
        asteroid.physicsBody?.collisionBitMask = 0
        
        scene.rootNode.addChildNode(asteroid)
        
        let move = SCNAction.move(to: SCNVector3(pos.x, 0, Float(limits.maxY)), duration: 3.0)
        let rotate = SCNAction.rotate(by: 10.0, around: randomAxis, duration: 3.0)
        let group = SCNAction.group([move, rotate])
        let remove = SCNAction.removeFromParentNode()
        
        asteroid.runAction(.sequence([group, remove]))
    }
    
    func shot() {
        guard let scene = self.scene, let ship = self.ship else { return }
        
        // TODO [B05]
        //  - Creamos una forma de tipo esfera (`SCNSphere`) con radio 1.0
        //  - Le asignamos en su `firstMaterial`, tanto `diffuse` como `emission`, en su propiedad `contents` el color (`UIColor`) con RGB (0.8, 0.7, 0.2)
        
        //  - Creamos la bala como un nodo `SCNNode` con la geometría de esfera anterior, dandole nombre "bullet", y ubicandola en la misma posicion que la nave.
        //  - Agregamos el nodo a la escena
        //  - Definimos una accion que mueva la bala 150 unidades negativas en el eje Z, y tras ello elimine la bala de la escena
        //  - Ejecutamos la accion sobre la bala
        let sphere = SCNSphere(radius: 1.0)
        sphere.firstMaterial?.diffuse.contents = UIColor(red: 0.8, green: 0.7, blue: 0.2, alpha: 1.0)
        sphere.firstMaterial?.emission.contents = UIColor(red: 0.8, green: 0.7, blue: 0.2, alpha: 1.0)
        
        let bullet = SCNNode(geometry: sphere)
        bullet.name = "bullet"
        bullet.position = ship.presentation.position
        scene.rootNode.addChildNode(bullet)
        
        let move = SCNAction.moveBy(x: 0, y: 0, z: -150, duration: 1.0)
        let remove = SCNAction.removeFromParentNode()
        bullet.runAction(.sequence([move, remove]))
        
        // TODO [C05] Crear cuerpo fisica en la bala, de tipo kinematic, esfera de radio 1, con categoria "categoryMaskShot"
        bullet.physicsBody = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: sphere, options: nil))
        bullet.physicsBody?.categoryBitMask = categoryMaskShot
        bullet.physicsBody?.contactTestBitMask = categoryMaskAsteroid
        bullet.physicsBody?.collisionBitMask = 0
    }
    
    func destroyAsteroid(asteroid: SCNNode, withBullet bullet: SCNNode) {

        showExplosion(onNode: asteroid)
        
        // TODO [C09] Elimina el asteroide y la bala de la escena
        asteroid.removeFromParentNode()
        bullet.removeFromParentNode()
        
        // TODO [C14]
        //  - Incrementa el numero de asteroides destruidos (numAsteroides) y actualiza el texto del marcadorAsteroides con "X HITS"
        numAsteroides += 1
        marcadorAsteroides?.text = "\(numAsteroides) HITS"
    }
    
    func destroyShip(ship: SCNNode, withAsteroid asteroid: SCNNode) {

        showExplosion(onNode: ship)

        // TOdO [C10] Elimina el asteroide, y haz que la nave salga despedida hacia atrás mientras rota alrededor de su eje Y.
        asteroid.removeFromParentNode()
        
        let moveBack = SCNAction.moveBy(x: 0, y: 0, z: 20, duration: 0.5)
        let rotate = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2.0, z: 0, duration: 0.5)
        ship.runAction(.group([moveBack, rotate]))
        
        // TODO [D13] Llamamos a showGameOver()
        showGameOver()
    }
    
    func showExplosion(onNode node: SCNNode) {
        // TODO [C12] Agreegar el efecto de particulas explode a la escena en la posicion de node
        if let explosion = self.explosion {
            let explosionNode = SCNNode()
            explosionNode.position = node.presentation.position
            explosionNode.addParticleSystem(explosion)
            scene?.rootNode.addChildNode(explosionNode)
            
            let wait = SCNAction.wait(duration: 2.0)
            let remove = SCNAction.removeFromParentNode()
            explosionNode.runAction(.sequence([wait, remove]))
        }
        
        // TODO [C17] Reproduce el sonido soundExplosion en la posicion de node
        if let soundExplosion = self.soundExplosion {
            let audioNode = SCNNode()
            audioNode.position = node.presentation.position
            scene?.rootNode.addChildNode(audioNode)
            audioNode.runAction(.playAudio(soundExplosion, waitForCompletion: false))
            audioNode.runAction(.sequence([.wait(duration: 1.0), .removeFromParentNode()]))
        }
    }
        
    // MARK: - Metodos para cambio de estado
    
    func showTitle() {
        // TODO [D09]
        //  - Cambiar el estado a `Title`
        //  - Mostrar `titleGroup`
        //  - Ocultar `gameOverGroup`
        //  - Ocultar el HUD
        //  - Ocultar la nave
        gameState = .title
        titleGroup?.isHidden = false
        gameOverGroup?.isHidden = true
        hud?.isHidden = true
        ship?.isHidden = true
        previousUpdateTime = nil
    }
    
    func showGameOver() {
        // TODO [D12]
        //  - Cambiar el estado a `GameOver`
        //  - Ocultar el HUD
        //  - Mostrar 'gameOverGroup'
        
        //  - Poner en `gameOverResultsText` el texto "X ASTEROIDS DESTROYED"
        
        //  - Inicializar la posición de `gameOverGroup en (0, 0, 0)
        //  - Inicializar la opacidad de `gameOverGroup a 1
        //  - Ejecutamos una acción que mueva `gameOverGroup` a (0, 0, -200) en 2 segundos, con modificador de tiempo `easeOut`, y tras ello haga un fadeout del nodo en 0.5 segundos y llame a showTitle() para volver al titulo.
        gameState = .gameOver
        hud?.isHidden = true
        gameOverGroup?.isHidden = false
        
        gameOverResultsText?.string = "\(numAsteroides) ASTEROIDS DESTROYED"
        if let resultsNode = gameOverGroup?.childNodes.last {
            centerPivot(of: resultsNode)
        }
        
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
        // TODO [D10]
        //  - Cambiar el estado a `Introduction`
        //  - Ocultar `titleGroup`
        //  - Mostrar el HUD
        //  - Mostrar la nave
        
        //  - Poner a '0' el contador de asteroides destruidos
        //  - Poner como cadena vacía el texto del marcador de asteroides destruidos
        
        //  - Inicializar la posición de la nave en (0, 50, 50)
        //  - Ejecutamos una acción que mueva la nave a la posición (0, 0, 0) en un segundo y tras esto pase a estado a `Playing`
        gameState = .introduction
        titleGroup?.isHidden = true
        gameOverGroup?.isHidden = true
        hud?.isHidden = false
        ship?.isHidden = false
        
        numAsteroides = 0
        marcadorAsteroides?.text = ""
        
        ship?.removeAllActions()
        ship?.position = SCNVector3(0, 50, 50)
        ship?.eulerAngles = SCNVector3Zero
        
        let move = SCNAction.move(to: SCNVector3(0, 0, 0), duration: 1.0)
        let finish = SCNAction.run { [weak self] _ in
            self?.gameState = .playing
            self?.marcadorAsteroides?.text = "0 HITS"
            self?.timeToSpawn = TimeInterval(self?.spawnInterval ?? 0.25)
            self?.previousUpdateTime = nil
        }
        
        ship?.runAction(.sequence([move, finish]))
    }
    
    // MARK: - Eventos de SCNSceneRendererDelegate (bucle del juego)
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // TODO [B09] Calcular el delta time tomando como referencia previousUpdateTime, y actualizar previousUpdateTime
        let deltaTime: TimeInterval
        if let previous = previousUpdateTime {
            deltaTime = time - previous
        } else {
            deltaTime = 0
        }
        previousUpdateTime = time
        
        // TODO [D03] Solo generamos asteroides y movemos la nave en estado "Playing"
        guard gameState == .playing, let ship = self.ship else { return }
        
        // TODO [C03] Spawn de asteroides
        //  - Descontamos el deltatime de timeToSpawn, y cuando este llegue a 0 generamos un nuevo asteroide y restablecemos el valor de timeToSpawn a spawnInterval.
        //  - El asteroide debe generarse en una posicion X aleatoria entre los limites de la escena (limits.minX y limits.maxX), Y=0, y Z=limits.minY
        timeToSpawn -= deltaTime
        if timeToSpawn <= 0 {
            let randomX = Float.getRandom(from: Float(limits.minX), to: Float(limits.maxX))
            let spawnPos = SCNVector3(randomX, 0, Float(limits.minY))
            spawnAsteroid(pos: spawnPos)
            timeToSpawn = TimeInterval(spawnInterval)
        }

        // TODO [B10] Mueve la nave lateralmente a partir de `velocity * 200` y el deltatime, evita que se salga de los limites de pantalla (`limits`) y gira la nave en el eje Z según el valor de `velocity`
        let nextX = ship.position.x + velocity * 200.0 * Float(deltaTime)
        let minX = Float(limits.minX)
        let maxX = Float(limits.maxX)
        
        ship.position.x = max(minX, min(maxX, nextX))
        ship.eulerAngles.z = -velocity * 0.75
    }
    
    // MARK: - Eventos de SCNPhysicsContactDelegate
    
    // TODO [C08] Definir el método `physicsWorld(:, didBegin:)` para detectar los contactos entre asteroides y balas o asteroides y la nave, y llamar a destroyShip() o destroyAsteroid() segun corresponda
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
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
    
    
    // MARK: - Eventos de la pantalla tactil
    
    @objc
    func handleTap(_ gestureRecognize: UIGestureRecognizer) {
        // TODO [D04] Disparamos solo si el estado es "Playing"
        if gameState == .playing {
            shot()
            return
        }
        
        // TODO [D11] Si el estado es "Title", llamamos a "startGame()"
        if gameState == .title {
            startGame()
        }
    }
    
    // MARK: - Orientación del controlador
    
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
