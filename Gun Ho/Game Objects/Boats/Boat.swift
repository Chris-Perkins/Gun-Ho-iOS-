//
//  SmallBoat.swift
//  Gun Ho
//
//  Created by Christopher Perkins on 2/11/18.
//  Copyright © 2018 Christopher Perkins. All rights reserved.
//

import SceneKit

class Boat: GameObject {
    
    class var pointsCount: Int { return  0 }
    
    var maxHealth: Int
    
    // How high the boat floats (negative is sync)
    var floatHeight: Float
    
    // How many points the boat is worth
    let pointValue: Int
    
    // The speed of our boat in m/s
    let speed: Int
    
    var health: Int {
        didSet {
            if health <= 0 {
                destroy()
            }
        }
    }
    
    // MARK: - Lifecycle
    init(maxHealth: Int, floatHeight: Float, points: Int, speed: Int, withNode node: SCNNode) {
        self.maxHealth   = maxHealth
        self.floatHeight = floatHeight
        self.pointValue  = points
        self.speed       = speed
        
        health = maxHealth
        
        super.init()
        
        addChildNode(node)
        
        guard let boatPhysicsBody = node.physicsBody else {
            fatalError("Could not get boat physics body! Does it exist?")
        }
        boatPhysicsBody.categoryBitMask  = CollisionType.boat
        boatPhysicsBody.collisionBitMask = CollisionType.boat
    }
    
    required override init() {
        fatalError("Cannot initialize a boat directly!")
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: Boat operations
    
    public func decrementHealth() {
        health -= 1
    }
    
    // Does nothing besides shake the boat object. called on boat tap.
    public func shake() {
        // FURTHER TODO: What the heck is up with gimbal lock?
        // Can we mathematically make this rotate nicely?
        // Is this even worth doing?
        
        let shakeTime = 0.2
        let shakeMax  = (10 / 180) * 3.14159
        let shakeAmount = SCNVector3(Double.random * shakeMax * 1/2,
                                     Double.random * shakeMax * 1/2,
                                     Double.random * shakeMax)
        
        ActionQueue(withActions: [
            // Tip the boat
            Action(actionTime: shakeTime,
                            withActions: {
                                SCNTransaction.perform {
                                    SCNTransaction.animationDuration = shakeTime
                                    self.eulerAngles += shakeAmount
                                }
            }),
            // Tip the boat back to the other side
            // * 2 as we have 2 times the distance to cover
            Action(actionTime: shakeTime * 2,
                   withActions: {
                        SCNTransaction.perform {
                            SCNTransaction.animationDuration = shakeTime * 2
                            self.eulerAngles -= shakeAmount * 2
                        }
            }),
            // Bring back to neutral position
            Action(actionTime: shakeTime,
                   withActions: {
                        SCNTransaction.perform {
                            SCNTransaction.animationDuration = shakeTime
                            self.eulerAngles += shakeAmount
                        }
            })
        ]).start()
    }
    
    // Should be called whenever the boat should be deleted
    public func destroy() {
        GameManager.shared.addPoints(pointValue)
        removeFromParentNode()
    }
    
    // Should be called when the boat is spawned
    // Causes boat to look at the island, pop up, then move towards the island
    public func performSpawnOperations() {
        // Keep a reference to the original scale for popping boat up
        let originalScale = GameManager.shared.gameNode.scale
        
        // Set the boat to be invisble and then "pop" it out.
        scale = SCNVector3(0, 0, 0)
        // The boat looks at the island on spawn for realistic movement
        /* NOTE: This uses global position because the look function
         looks at the GLOBAL position, not a local one. */
        look(at: SCNVector3(GameManager.shared.island.worldPosition.x,
                            worldPosition.y, // Look straight ahead
                            GameManager.shared.island.worldPosition.z))
        
        /*
         Springs the boat up. While springing up, the boat will start
         moving towards the island.
         */
        SCNTransaction.perform {
            SCNTransaction.animationDuration = 1
            self.scale = originalScale
        }
        
        SCNTransaction.perform {
            // Move linearly (default is ease in/out)
            SCNTransaction.animationTimingFunction =
                CAMediaTimingFunction.init(name: kCAMediaTimingFunctionLinear)
            
            // The 60 in this equation is a fake unit saying our ocean has a diameter of 60
            // Note... It doesn't.
            let distanceToCenter = 60.0 * GameManager.shared.ocean.scale.x / 2.0
            let timeToCenter = distanceToCenter / Float(self.speed)
            
            SCNTransaction.animationDuration = CFTimeInterval(timeToCenter)
            self.position = SCNVector3(0, self.position.y, 0)
        }
    }
}