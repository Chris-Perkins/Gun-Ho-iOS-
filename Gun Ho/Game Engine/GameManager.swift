//
//  GameManager.swift
//  Gun Ho
//
//  Created by Christopher Perkins on 2/14/18.
//  Copyright © 2018 Christopher Perkins. All rights reserved.
//

/*
 REASON FOR CREATION:
 At time of writing, there is no easy way to update logic every frame
 The GameManager takes care of this.
 */

import SceneKit
import ARKit

// MARK: Main declaration (Singleton / Properties)

public class GameManager: NSObject {
    
    // MARK: Singleton logic
    
    private static var activeInstance: GameManager?
    
    // Returns or creates and returns the shared instance
    public static var shared: GameManager {
        if let instance = activeInstance {
            return instance
        } else {
            activeInstance = GameManager()
            return activeInstance!
        }
    }
    
    override private init() {}
    
    // MARK: Game properties
    
    // The delegate we inform of game state changes
    internal var delegate: GameManagerDelegate?
    
    // The root node for use in spawning and finding the worldScene node
    public var rootNode: SCNNode? {
        didSet {
            guard let islandEnvironment = island.childNode(withName: "environment",
                                                           recursively: false),
                let islandPhysicsBody = islandEnvironment.physicsBody else {
                fatalError("Could not get island/it's physics body!")
            }
            islandPhysicsBody.categoryBitMask  = CollisionType.island
            islandPhysicsBody.collisionBitMask = CollisionType.island
        }
    }
    
    // Stores all game objects so we can check logic for each frame
    public var gameObjects = [GameObject]()
    
    // Whether or not the game has started
    private var hasStartedGame = false
    
    // The maximum wave we can go to
    /*
     NOTE: Make sure the summation from 0 to maxWave
     of pointsPerWave is < 2^32
     */
    private let maxWave = 100
    
    /* A reference to the object that is currently spawning boats
        Nullable since we may not be in an active game */
    private var boatSpawner: BoatSpawner?
    
    /* The current wave we're on
        Nullable since we may not be in an active game */
    private var curWave: Int?
    
    /* The total points we've earned in this session of the game
        Nullable since we may not be in an active game */
    private var totalPoints: Int?
    
    // The current number of boats we've destroyed
    // Nullable since we may not be in an active game
    /*
     Due to the setter observer, curWave should be set
     before curPoints is set
    */
    private var curPoints: Int? {
        didSet {
            /*
             If the game started or ended, don't bother checking
             if we moved to the next level.
            */
            guard let curPoints = curPoints,
                let curWave = curWave else {
                return
            }
            
            if curPoints >= pointsPerWave(curWave) {
                performWaveCompleteSequence()
            }
        }
    }
    
    /* The object which holds all objects relevant to the game
        Throws if the gameNode cannot be retrieved */
    lazy public var gameNode: SCNNode = {
        guard let gameNode = rootNode?.childNode(withName: "gameNode", recursively: false) else {
            fatalError("Could not get gameNode!")
        }
        return gameNode
    }()
    
    /* Gets the lights in the scene
        Throws if the lights cannot be retrieved */
    lazy public var lights: [SCNLight]? = {
        guard let lightsNode = gameNode.childNode(withName: "lights", recursively: true) else {
            return nil
        }
        return lightsNode.childNodes.map({ (node) -> SCNLight in
            return node.light!
        })
    }()
    
    /* Gets the worldScene from the rootnode
        Throws if the worldScene cannot be retrieved */
    lazy public var worldScene: SCNNode = {
        guard let worldSceneNode = gameNode.childNode(withName: "worldScene", recursively: false) else {
            fatalError("Could not get worldScene!")
        }
        return worldSceneNode
    }()
    
    /* Gets the island from the worldscene
        Throws if the island cannot be retrieved*/
    lazy public var island: SCNNode = {
        guard let islandNode = worldScene.childNode(withName: "island", recursively: false) else {
            fatalError("Could not find island in the worldScene")
        }
        return islandNode
    }()
    
    /* Gets the ocean from the worldscene
        Throws if the ocean cannot be retrieved */
    lazy public var ocean: SCNNode = {
        guard let oceanNode = worldScene.childNode(withName: "ocean", recursively: false) else {
            fatalError("Could not find ocean in the worldScene")
        }
        return oceanNode
    }()
}

// MARK: Core Game Logic

extension GameManager {
    
    // Called on every frame to update the lighting to the provided lighting intensity
    public func updateLightingIntensity(toLightIntensity lightIntensity: CGFloat) {
        if let lights = lights {
            for light in lights {
                light.intensity = lightIntensity
            }
        }
    }
    
    /* Starts the game if it hasn't been started
        Throws if the game was already started */
    public func startGame() {
        if !hasStartedGame {
            performGameStartSequence()
            hasStartedGame = true
        } else {
            fatalError("Game was declared to start twice, but this cannot happen.")
        }
    }
    
    /* Should be called to start the game
        Throws if wave is < 0 */
    private func performGameStartSequence(atWave wave: Int = 1) {
        if wave <= 0 {
            fatalError("Waves are 1-indexed. Please use a wave value > 0")
        }
        
        totalPoints = 0
        curPoints   = 0
        curWave     = wave
        
        startCurrentWave()
        delegate?.gameDidStart?()
    }
    
    // Should be called whenever the game should end
    private func performGameOverSequence() {
        delegate?.gameWillEnd?(withPointTotal: totalPoints!)
        
        totalPoints = nil
        curWave     = nil
        curPoints   = nil
        
        boatSpawner?.pauseSpawning()
        boatSpawner = nil
        
        for node in gameObjects {
            node.removeFromParentNode()
        }
        
        gameObjects.removeAll()
        
        hasStartedGame = false
    }
    
    private func startCurrentWave() {
        // Spawn a bird just for minor aesthetics
        spawnBird()
        createAndStartCurrentWaveBoatSpawner()
    }
    
    /* Should be called whenever the user defeats a wave
        Throws if curWave is nil */
    private func performWaveCompleteSequence() {
        guard let wave = curWave else {
            fatalError("Wave cannot be complete; the game was never started!")
        }
        
        // We shouldn't create the next wave is the wave was completed
        if wave >= maxWave {
            performGameOverSequence()
        }
        
        // Reset the points since we use this to check against current wave requirements
        curPoints = 0
        curWave   = wave + 1
        
        startCurrentWave()
    }
    
    /* Adds the input points to the current and totalPoints variables
        Throws if curPoints or totalPoints is nil */
    public func addPoints(_ points: Int) {
        guard let curPoints = curPoints,
            let totalPoints = totalPoints else {
            fatalError("Cannot add points; the game was never started!")
        }
        
        self.curPoints   = curPoints + points
        self.totalPoints = totalPoints + points
    }
    
    // Returns the number of points necessary to pass a wave
    private func pointsPerWave(_ wave: Int) -> Int {
        let linearFactor      = 3 * wave
        let exponentialFactor = 3^^(wave / 10 - 3)
        
        return linearFactor + exponentialFactor
    }
    
    /* Creates a boat spawner from the current wave's info.
        Requires a node to spawn on
        Throws if curWave is nil */
    private func createAndStartCurrentWaveBoatSpawner() {
        guard let curWave = curWave else {
                fatalError("Cannot create a spawner without the wave number")
        }
        
        boatSpawner = BoatSpawner(withPoints: pointsPerWave(curWave),
                                  andSpawningNode: gameNode)
        boatSpawner?.startSpawning()
    }
    
    // Creates a bird that flies around
    private func spawnBird() {
        let bird = Bird()
        worldScene.addChildNode(bird)
        bird.startFlying()
    }
}

// MARK: Physics delegate

extension GameManager: SCNPhysicsContactDelegate {
    public func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        let collisionMask = contact.nodeA.physicsBody!.collisionBitMask | contact.nodeB.physicsBody!.collisionBitMask
        
        switch collisionMask {
        case CollisionType.boat | CollisionType.island:
            performGameOverSequence()
        case CollisionType.boat | CollisionType.boat:
            /* The 'parent' is here since the physicsbody of the boat
                is attached to the immediate child of the boat object */
            (contact.nodeA.parent as? Boat)?.destroy()
            (contact.nodeA.parent as? Boat)?.destroy()
        default:
            // Unhandled collision, but not necessarily an error.
            break
        }
    }
}