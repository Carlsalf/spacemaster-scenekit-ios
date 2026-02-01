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
/*
public enum GameState {
    case ...
}
*/

// TODO [B07] Implementar protocolo SCNSceneRendererDelegate
// TODO [C06] Implementar protocolo SCNPhysicsContactDelegate
class GameViewController: UIViewController  {

    // TODO [D02] Definir campo `gameState` con el estado actual del juego
    
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
              
        // TODO [B03] Obtener el nodo "camara" de la escena, y almacenar su orientación original (eulerAngles)
        // self.cameraNode = ...
        // self.cameraEulerAngle = ...

        // TODO [B04] Obtener el nodo con la nave "ship" a partir de la escena
        // self.ship = ...

        // TODO [C11] Inicializamos efecto de particulas
        // self.explosion = ...

        // TODO [D08] Inicializa las referencias a las pantallas de titulo, gameover
        //self.titleGroup = ...
        //self.gameOverGroup = ...
        //self.gameOverResultsText = ...

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
        
        // Muestra la capa de la pantalla de titulo
        showTitle()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        let scnView = self.view as! SCNView
        
        setupLimits(forView: scnView)
        setupHUD(inView: scnView)
    }
    
    // MARK: - Metodos para la inicializacion de componentes
        
    func setupAudio(inScene scene: SCNScene) {
        // TODO [C15] Reproducir musica de fondo "rolemusic_step_to_space.mp3" en bucle, con volumen 0.1, y desde el nodo raiz de la escena.
        
        // TODO [C16] Precarga el efecto bomb.wav, con volumen 10.0, y asignalo al campo soundExplosion
        
    }
    
    func setupAsteroids(forView view: SCNView) {
        // TODO [C01] Precarga el modelo de asteroide "asteroid" de rock.scn, asignalo al campo asteroidModel, y preparalo para su visualización en view
    }
        
    func setupView(_ view: SCNView, withScene scene: SCNScene) {
        view.scene = scene
        view.allowsCameraControl = false
        view.showsStatistics = true
        view.backgroundColor = UIColor.black
        
        // TODO [B08] Asignar esta clase como delegado del renderer de la escena, y activar la propiedad `isPlaying` de la vista
    }

    func setupLimits(forView view: SCNView) {
        // TODO [B06] Calcular y almacenar en `self.limits` el rectángulo que defina los límites de la zona "jugable" dentro del plano XZ de la escena, donde la nave, disparos y asteroides se puedan mover sin salirse de los límites de la pantalla.
    }
    
    func setupHUD(inView view: SCNView) {
        // TODO [C13]
        //  - Crea una SKScene del tamaño de la vista y asignala a la capa overlaySKScene de la vista
        //  - Crea un SKLabel con cadena "0 HITS" con fuente University, de tamaño 36 y color naranja
        //  - Situa la etiqueta en la parte superior de la pantalla, centrada en la horizontal, haciendo que todo el texto quede visible en pantalla
        
        //  - Asigna la etiqueta y la escena a los siguientes campos:
        //     self.marcadorAsteroides = ...
        //     self.hud = ...
    }

    // MARK: - Metodos para la inicializacion de los controles
    
    func startTapRecognition(inView view: SCNView) {
        // TODO [B01] Programar un UITapGestureRecognizer y agregarlo a la vista (view)
        
    }
    
    func startMotionUpdates() {
        // TODO [B02] Implementar el control mediante Core Motion
        //  - Comprobar en self.motion is Device Motion esta disponible
        //  - Programar el intervalo de refreso de Device Motion updates en 1.0 / 60.0
        //  - Comenzamos la lectura de Device Motion updates
        //  - Hacemos que el ángulo de giro "roll" sea la velocidad (self.velocity) de nuestra nave
        //  - Orientamos la cámara utilizando pitch (eulerAngles.x) y roll (eurlerAngles.z)
    }
    
    // MARK: - Metodos para los eventos del juego
    
    func spawnAsteroid(pos: SCNVector3) {
        
        // TODO [C02] Clonar el asteroide "asteroidModel", y asignar las siguiente propiedades:
        //  - Agregar el nuevo asteroide a la escena (nodo raiz)
        //  - Situarlo en pos
        //  - Hacer que se mueva hasta (pos.x, 0, limits.maxY) en 3 segundos
        //  - Hacer que al mismo tiempo el asteroide rote sobre un eje aleatorio, 10 radianes, en 3 segundos
        //  - Tras llegar a su posicion final, debera ser eliminado de la escena.
    }
    
    func shot() {
        // TODO [B05]
        //  - Creamos una forma de tipo esfera (`SCNSphere`) con radio 1.0
        //  - Le asignamos en su `firstMaterial`, tanto `diffuse` como `emission`, en su propiedad `contents` el color (`UIColor`) con RGB (0.8, 0.7, 0.2)
        
        //  - Creamos la bala como un nodo `SCNNode` con la geometría de esfera anterior, dandole nombre "bullet", y ubicandola en la misma posicion que la nave.
        //  - Agregamos el nodo a la escena
        //  - Definimos una accion que mueva la bala 150 unidades negativas en el eje Z, y tras ello elimine la bala de la escena
        //  - Ejecutamos la accion sobre la bala

        
        // TODO [C05] Crear cuerpo fisica en la bala, de tipo kinematic, esfera de radio 1, con categoria "categoryMaskShot"

    }
    
    func destroyAsteroid(asteroid: SCNNode, withBullet bullet: SCNNode) {

        showExplosion(onNode: asteroid)
        
        // TODO [C09] Elimina el asteroide y la bala de la escena
        
        // TODO [C14]
        //  - Incrementa el numero de asteroides destruidos (numAsteroides) y actualiza el texto del marcadorAsteroides con "X HITS"
    }
    
    func destroyShip(ship: SCNNode, withAsteroid asteroid: SCNNode) {

        showExplosion(onNode: ship)

        // TOdO [C10] Elimina el asteroide, y haz que la nave salga despedida hacia atrás mientras rota alrededor de su eje Y.
        
        // TODO [D13] Llamamos a showGameOver()
    }
    
    func showExplosion(onNode node: SCNNode) {
        // TODO [C12] Agreegar el efecto de particulas explode a la escena en la posicion de node
        
        // TODO [C17] Reproduce el sonido soundExplosion en la posicion de node

    }
        
    // MARK: - Metodos para cambio de estado
    
    func showTitle() {
        // TODO [D09]
        //  - Cambiar el estado a `Title`
        //  - Mostrar `titleGroup`
        //  - Ocultar `gameOverGroup`
        //  - Ocultar el HUD
        //  - Ocultar la nave
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
    }
    
    // MARK: - Eventos de SCNSceneRendererDelegate (bucle del juego)
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // TODO [B09] Calcular el delta time tomando como referencia previousUpdateTime, y actualizar previousUpdateTime
        
        
        // TODO [D03] Solo generamos asteroides y movemos la nave en estado "Playing"
        
        
        // TODO [C03] Spawn de asteroides
        //  - Descontamos el deltatime de timeToSpawn, y cuando este llegue a 0 generamos un nuevo asteroide y restablecemos el valor de timeToSpawn a spawnInterval.
        //  - El asteroide debe generarse en una posicion X aleatoria entre los limites de la escena (limits.minX y limits.maxX), Y=0, y Z=limits.minY

        
        // TODO [B10] Mueve la nave lateralmente a partir de `velocity * 200` y el deltatime, evita que se salga de los limites de pantalla (`limits`) y gira la nave en el eje Z según el valor de `velocity`
    }
    
    // MARK: - Eventos de SCNPhysicsContactDelegate
    
    // TODO [C08] Definir el método `physicsWorld(:, didBegin:)` para detectar los contactos entre asteroides y balas o asteroides y la nave, y llamar a destroyShip() o destroyAsteroid() segun corresponda
    
    
    // MARK: - Eventos de la pantalla tactil
    
    @objc
    func handleTap(_ gestureRecognize: UIGestureRecognizer) {

        shot()
        // TODO [D04] Disparamos solo si el estado es "Playing"
        // TODO [D11] Si el estado es "Title", llamamos a "startGame()"
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
