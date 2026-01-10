// ABOUTME: Core session manager handling device discovery, distance tracking, and collision detection.
// ABOUTME: Bridges MultipeerConnectivity (discovery) with Nearby Interaction (UWB distance/direction).

import Foundation
import NearbyInteraction
import MultipeerConnectivity
import Combine
import UIKit
import simd
import CoreHaptics

class BumperSession: NSObject, ObservableObject {
    // MARK: - Published State

    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var distance: Float?
    @Published var direction: simd_float3?
    @Published var peersFound: Int = 0
    @Published var isConnected: Bool = false

    // Collision feedback
    @Published var showCollisionIndicator: Bool = false
    @Published var collisionPosition: CGPoint = .zero
    @Published var collisionIntensity: CGFloat = 0

    // Debug
    @Published var debugLog: String = ""
    @Published var debugDetails: String = ""  // More detailed debug info
    @Published var directionSupported: Bool? = nil  // nil = unknown, false = not supported, true = supported

    // MARK: - Private Properties

    private var niSession: NISession?
    private var mcSession: MCSession?
    private var mcAdvertiser: MCNearbyServiceAdvertiser?
    private var mcBrowser: MCNearbyServiceBrowser?
    private var connectedPeer: MCPeerID?

    private let serviceType = "bumper-cars"
    private let myPeerID: MCPeerID

    // Collision detection state
    private var distanceHistory: [(timestamp: Date, distance: Float)] = []
    private var lastCollisionTime: Date?
    private let collisionCooldown: TimeInterval = 0.5
    private var lastKnownDirection: simd_float3?

    // Haptic generators (legacy - kept for fallback)
    private let impactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    
    // Core Haptics engine for advanced haptic patterns
    private var hapticEngine: CHHapticEngine?
    private var hapticEngineSupported: Bool = false

    // Phone geometry (meters) - UWB chip is near top-center of phone
    private let phoneGeometry: PhoneGeometry = PhoneGeometry.current()

    private func logPhoneGeometry() {
        log("Phone: h=\(Int(phoneGeometry.height*1000))mm w=\(Int(phoneGeometry.width*1000))mm chip=\(Int(phoneGeometry.chipFromTop*1000))mm from top")
    }

    // MARK: - Init

    override init() {
        self.myPeerID = MCPeerID(displayName: UIDevice.current.name)
        super.init()
        impactGenerator.prepare()
        notificationGenerator.prepare()
        setupCoreHaptics()
    }
    
    // MARK: - Core Haptics Setup
    
    private func setupCoreHaptics() {
        // Check if device supports Core Haptics
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            print("[Haptics] Core Haptics not supported on this device")
            hapticEngineSupported = false
            return
        }
        
        hapticEngineSupported = true
        
        do {
            hapticEngine = try CHHapticEngine()
            
            // Handle engine stopped/reset
            hapticEngine?.stoppedHandler = { [weak self] reason in
                print("[Haptics] Engine stopped: \(reason)")
                // Try to restart
                self?.restartHapticEngine()
            }
            
            hapticEngine?.resetHandler = { [weak self] in
                print("[Haptics] Engine reset")
                self?.restartHapticEngine()
            }
            
            try hapticEngine?.start()
            print("[Haptics] Core Haptics engine started successfully")
        } catch {
            print("[Haptics] Failed to create haptic engine: \(error)")
            hapticEngineSupported = false
        }
    }
    
    private func restartHapticEngine() {
        guard hapticEngineSupported else { return }
        
        do {
            try hapticEngine?.start()
        } catch {
            print("[Haptics] Failed to restart engine: \(error)")
        }
    }

    // MARK: - Public Methods

    func start() {
        let model = getDeviceModelIdentifier()
        log("Starting... Device: \(myPeerID.displayName)")
        print("[Bumper] ======================================")
        print("[Bumper] Device Model: \(model)")
        print("[Bumper] Expected models for iPhone 15 Pro: iPhone16,1 or iPhone16,2")
        print("[Bumper] iOS Version: \(UIDevice.current.systemVersion)")
        print("[Bumper] NI Supported: \(NISession.isSupported)")
        
        // Check capabilities early
        if #available(iOS 16.0, *) {
            let caps = NISession.deviceCapabilities
            print("[Bumper] Di  rection Measurement: \(caps.supportsDirectionMeasurement)")
            print("[Bumper] Precise Distance: \(caps.supportsPreciseDistanceMeasurement)")
            print("[Bumper] Camera Assistance: \(caps.supportsCameraAssistance)")
            
            // NOTE: If supportsDirectionMeasurement is false on iPhone 11+,
            // it likely means the Nearby Interaction entitlement is not configured.
            // Go to Apple Developer Portal → App IDs → Enable "Nearby Interaction" capability
            // Then in Xcode: Signing & Capabilities → Add "Nearby Interaction"
            if !caps.supportsDirectionMeasurement {
                print("[Bumper] ⚠️ Direction not supported - likely missing entitlement!")
                print("[Bumper] See: Apple Developer Portal → App IDs → Nearby Interaction")
            }
        }
        print("[Bumper] ======================================")
        
        setupMultipeerConnectivity()
        connectionStatus = .searching
    }

    private func log(_ message: String) {
        print("[Bumper] \(message)")
        DispatchQueue.main.async {
            self.debugLog = message
        }
    }

    func stop() {
        mcAdvertiser?.stopAdvertisingPeer()
        mcBrowser?.stopBrowsingForPeers()
        mcSession?.disconnect()
        niSession?.invalidate()
        niSession = nil
        
        // Stop haptic engine
        hapticEngine?.stop()
        
        connectionStatus = .disconnected
        isConnected = false
    }

    // MARK: - MultipeerConnectivity Setup

    private func setupMultipeerConnectivity() {
        mcSession = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        mcSession?.delegate = self

        // Both advertise and browse simultaneously
        mcAdvertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: nil,
            serviceType: serviceType
        )
        mcAdvertiser?.delegate = self
        mcAdvertiser?.startAdvertisingPeer()

        mcBrowser = MCNearbyServiceBrowser(
            peer: myPeerID,
            serviceType: serviceType
        )
        mcBrowser?.delegate = self
        mcBrowser?.startBrowsingForPeers()

        print("[MC] Started advertising and browsing")
    }

    // MARK: - Nearby Interaction Setup

    private func setupNearbyInteraction() {
        guard NISession.isSupported else {
            log("NI not supported on this device!")
            return
        }

        // Check device capabilities in detail
        print("[NI] ============ DEVICE CAPABILITIES ============")
        print("[NI] Device: \(UIDevice.current.name)")
        print("[NI] Model: \(getDeviceModelIdentifier())")
        print("[NI] iOS: \(UIDevice.current.systemVersion)")
        print("[NI] NI supported: \(NISession.isSupported)")
        
        if #available(iOS 16.0, *) {
            let caps = NISession.deviceCapabilities
            print("[NI] supportsDirectionMeasurement: \(caps.supportsDirectionMeasurement)")
            print("[NI] supportsPreciseDistanceMeasurement: \(caps.supportsPreciseDistanceMeasurement)")
            print("[NI] supportsCameraAssistance: \(caps.supportsCameraAssistance)")
            
            // Log this to UI for easier debugging
            DispatchQueue.main.async {
                let model = self.getDeviceModelIdentifier()
                let iosVersion = UIDevice.current.systemVersion
                self.debugDetails = """
                Device: \(model)
                iOS: \(iosVersion)
                Direction: \(caps.supportsDirectionMeasurement ? "✅ YES" : "❌ NO")
                Precise Distance: \(caps.supportsPreciseDistanceMeasurement ? "✅" : "❌")
                Camera Assist: \(caps.supportsCameraAssistance ? "✅" : "❌")
                """
                self.debugLog = "Dir:\(caps.supportsDirectionMeasurement) Dist:\(caps.supportsPreciseDistanceMeasurement)"
            }
            
            if !caps.supportsDirectionMeasurement {
                print("[NI] ⚠️ WARNING: This device does NOT support direction measurement!")
                print("[NI] This is unexpected for iPhone 11+ with U1 chip")
                print("[NI] Possible causes:")
                print("[NI]   - Running in Simulator (UWB not simulated)")
                print("[NI]   - Device has hardware issue")
                print("[NI]   - iOS bug - try restarting device")
            }
        } else {
            print("[NI] iOS < 16 - capability checks unavailable")
            DispatchQueue.main.async {
                self.debugDetails = "iOS < 16.0 - capability checks unavailable"
            }
        }
        print("[NI] ==============================================")

        // NOTE: NearbyInteraction permission is requested automatically by iOS
        // when you create an NISession. The system will show a permission prompt
        // based on NSNearbyInteractionUsageDescription in Info.plist.
        // There's no explicit requestAuthorization() API like camera/location.
        
        print("[NI] Creating NISession (this will trigger permission prompt if first time)...")
        niSession = NISession()
        niSession?.delegate = self
        
        // Log session info
        print("[NI] NISession created, delegateQueue: \(String(describing: niSession?.delegateQueue))")

        // Accessing discoveryToken may also trigger permission prompt
        print("[NI] Getting discovery token (may trigger permission if not already granted)...")
        guard let token = niSession?.discoveryToken else {
            log("Failed to get NI discovery token - permission may have been denied")
            print("[NI] ⚠️ If this fails, check:")
            print("[NI]   1. Settings → Privacy → Nearby Interaction")
            print("[NI]   2. Info.plist has NSNearbyInteractionUsageDescription")
            print("[NI]   3. User granted permission when prompted")
            return
        }
        
        print("[NI] ✅ Discovery token obtained - permission granted!")

        sendDiscoveryToken(token)
        log("NI token sent, waiting for peer...")
    }
    
    private func getDeviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        } ?? "Unknown"
    }

    private func sendDiscoveryToken(_ token: NIDiscoveryToken) {
        guard let mcSession = mcSession,
              let peer = connectedPeer else {
            log("Cannot send token - no peer")
            return
        }

        do {
            // Create a message containing both the token and our capabilities
            var capsInfo: [String: Bool] = [:]
            if #available(iOS 16.0, *) {
                let caps = NISession.deviceCapabilities
                capsInfo["supportsDirection"] = caps.supportsDirectionMeasurement
                capsInfo["supportsPreciseDistance"] = caps.supportsPreciseDistanceMeasurement
                capsInfo["supportsCameraAssistance"] = caps.supportsCameraAssistance
            }
            
            let tokenData = try NSKeyedArchiver.archivedData(
                withRootObject: token,
                requiringSecureCoding: true
            )
            
            // Wrap in a dictionary with type identifier
            let message: [String: Any] = [
                "type": "discoveryToken",
                "token": tokenData,
                "capabilities": capsInfo,
                "deviceModel": getDeviceModelIdentifier(),
                "iosVersion": UIDevice.current.systemVersion
            ]
            
            let messageData = try NSKeyedArchiver.archivedData(
                withRootObject: message,
                requiringSecureCoding: false
            )
            try mcSession.send(messageData, toPeers: [peer], with: .reliable)
            print("[NI] Sent token with capabilities: \(capsInfo)")
        } catch {
            log("Failed to send token: \(error.localizedDescription)")
        }
    }

    private func handleReceivedToken(_ data: Data) {
        do {
            // Try new format first (with capabilities)
            if let message = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSDictionary.self, NSString.self, NSData.self, NSNumber.self], from: data) as? [String: Any],
               let type = message["type"] as? String,
               type == "discoveryToken",
               let tokenData = message["token"] as? Data {
                
                // Log peer capabilities
                if let peerCaps = message["capabilities"] as? [String: Bool] {
                    let peerModel = message["deviceModel"] as? String ?? "?"
                    let peerIOS = message["iosVersion"] as? String ?? "?"
                    
                    print("[NI] ============ PEER CAPABILITIES ============")
                    print("[NI] Peer device: \(connectedPeer?.displayName ?? "?")")
                    print("[NI] Peer model: \(peerModel)")
                    print("[NI] Peer iOS: \(peerIOS)")
                    print("[NI] Peer supportsDirection: \(peerCaps["supportsDirection"] ?? false)")
                    print("[NI] Peer supportsPreciseDistance: \(peerCaps["supportsPreciseDistance"] ?? false)")
                    print("[NI] Peer supportsCameraAssistance: \(peerCaps["supportsCameraAssistance"] ?? false)")
                    print("[NI] =============================================")
                    
                    // Check if direction will work
                    let peerSupportsDir = peerCaps["supportsDirection"] ?? false
                    var localSupportsDir = false
                    if #available(iOS 16.0, *) {
                        localSupportsDir = NISession.deviceCapabilities.supportsDirectionMeasurement
                    }
                    
                    if !peerSupportsDir || !localSupportsDir {
                        print("[NI] ⚠️ DIRECTION WILL BE NIL - one or both devices don't support it!")
                        print("[NI]   Local supportsDirection: \(localSupportsDir)")
                        print("[NI]   Peer supportsDirection: \(peerSupportsDir)")
                    } else {
                        print("[NI] ✅ Both devices support direction measurement")
                    }
                }
                
                guard let token = try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: NIDiscoveryToken.self,
                    from: tokenData
                ) else {
                    log("Failed to decode peer token from new format")
                    return
                }
                
                startNISession(with: token)
                return
            }
            
            // Fall back to old format (just the token)
            guard let token = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: NIDiscoveryToken.self,
                from: data
            ) else {
                log("Failed to decode peer token")
                return
            }

            print("[NI] Received token in old format (no capability info)")
            startNISession(with: token)
        } catch {
            log("Token decode error: \(error.localizedDescription)")
        }
    }
    
    private func startNISession(with token: NIDiscoveryToken) {
        let config = NINearbyPeerConfiguration(peerToken: token)
        
        // Log configuration details
        print("[NI] ============ SESSION START ============")
        print("[NI] Creating NINearbyPeerConfiguration")
        if #available(iOS 16.0, *) {
            let caps = NISession.deviceCapabilities
            print("[NI] Device capabilities at session start:")
            print("[NI]   supportsDirectionMeasurement: \(caps.supportsDirectionMeasurement)")
            print("[NI]   supportsPreciseDistanceMeasurement: \(caps.supportsPreciseDistanceMeasurement)")
            print("[NI]   supportsCameraAssistance: \(caps.supportsCameraAssistance)")
        }
        
        niSession?.run(config)
        log("NI session started! Tracking distance...")
        
        print("[NI] Session is now running - waiting for updates...")
        print("[NI] NOTE: Direction may still work even if capability says false!")
        print("[NI] =======================================")

        DispatchQueue.main.async {
            self.connectionStatus = .connected
            self.isConnected = true
        }
    }

    // MARK: - Collision Detection

    private var lastMinDistance: Float = 999

    private func processDistanceUpdate(_ newDistance: Float, direction: simd_float3?) {
        let now = Date()

        // Add to history
        distanceHistory.append((timestamp: now, distance: newDistance))

        // Keep only last 500ms of history
        distanceHistory.removeAll { now.timeIntervalSince($0.timestamp) > 0.5 }

        // Check cooldown
        if let lastCollision = lastCollisionTime,
           now.timeIntervalSince(lastCollision) < collisionCooldown {
            lastMinDistance = min(lastMinDistance, newDistance)
            return
        }

        // Reset min distance tracker after cooldown
        lastMinDistance = newDistance

        // TRIGGER 1: Proximity-based with direction-aware threshold
        // Calculate expected chip distance based on which edge is facing the other phone
        let threshold = phoneGeometry.collisionThreshold(for: direction)

        if newDistance < threshold {
            let intensity = max(0.6, 1.0 - (newDistance / threshold))
            triggerCollision(direction: direction, intensity: intensity)
            return
        }

        // Need samples for rate-based detection
        guard distanceHistory.count >= 3 else { return }

        // Calculate approach rate (negative = getting closer)
        let recentSamples = distanceHistory.suffix(5)
        guard let firstSample = recentSamples.first,
              let lastSample = recentSamples.last,
              firstSample.timestamp != lastSample.timestamp else {
            return
        }

        let timeDelta = lastSample.timestamp.timeIntervalSince(firstSample.timestamp)
        let distanceDelta = lastSample.distance - firstSample.distance
        let approachRate = distanceDelta / Float(timeDelta)

        // TRIGGER 2: Rapid approach - must be close to threshold AND approaching fast
        let isApproachingFast = approachRate < -0.5
        let nearThreshold = newDistance < threshold * 1.5

        if isApproachingFast && nearThreshold {
            let intensity = min(1.0, abs(approachRate))
            triggerCollision(direction: direction, intensity: intensity)
            return
        }

        // TRIGGER 3: Sudden stop after approach - must end up very close
        if distanceHistory.count >= 6 {
            let olderSamples = Array(distanceHistory.prefix(3))
            if let oldFirst = olderSamples.first,
               let oldLast = olderSamples.last {
                let oldTimeDelta = oldLast.timestamp.timeIntervalSince(oldFirst.timestamp)
                if oldTimeDelta > 0 {
                    let oldDistanceDelta = oldLast.distance - oldFirst.distance
                    let oldApproachRate = oldDistanceDelta / Float(oldTimeDelta)

                    let wasApproachingFast = oldApproachRate < -0.5
                    let nowStopped = approachRate > -0.1
                    let veryClose = newDistance < threshold * 1.2

                    if wasApproachingFast && nowStopped && veryClose {
                        triggerCollision(direction: direction, intensity: min(1.0, abs(oldApproachRate)))
                        return
                    }
                }
            }
        }
    }

    private func triggerCollision(direction: simd_float3?, intensity: Float) {
        lastCollisionTime = Date()

        // Calculate collision position - push to screen edge based on direction
        var position = CGPoint.zero
        var edgeName = "center"

        if let dir = direction {
            // x = left/right, y = toward top/bottom edge, z = up into air
            let absX = abs(dir.x)
            let absY = abs(dir.y)

            if absX > absY {
                // Side collision
                position = CGPoint(x: dir.x > 0 ? 1.0 : -1.0, y: 0)
                edgeName = dir.x > 0 ? "RIGHT" : "LEFT"
            } else {
                // Top/bottom collision
                position = CGPoint(x: 0, y: dir.y > 0 ? 1.0 : -1.0)
                edgeName = dir.y > 0 ? "TOP" : "BOTTOM"
            }
        }

        log("BUMP! \(edgeName)")

        // Determine collision direction for haptics
        let hapticDirection: CollisionDirection
        switch edgeName {
        case "LEFT": hapticDirection = .left
        case "RIGHT": hapticDirection = .right
        case "TOP": hapticDirection = .top
        case "BOTTOM": hapticDirection = .bottom
        default: hapticDirection = .center
        }

        DispatchQueue.main.async {
            // Trigger directional haptic
            self.triggerHaptic(intensity: intensity, direction: hapticDirection)

            // Show visual indicator
            self.collisionPosition = position
            self.collisionIntensity = CGFloat(intensity)
            self.showCollisionIndicator = true

            // Hide after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showCollisionIndicator = false
            }
        }
    }

    private func triggerHaptic(intensity: Float, direction: CollisionDirection = .center) {
        // Use Core Haptics if available, otherwise fall back to legacy
        if hapticEngineSupported, let engine = hapticEngine {
            triggerCoreHaptic(intensity: intensity, direction: direction, engine: engine)
        } else {
            triggerLegacyHaptic(intensity: intensity)
        }
    }
    
    enum CollisionDirection {
        case left, right, top, bottom, center
        
        var hapticPattern: HapticPattern {
            switch self {
            case .left:
                return HapticPattern(
                    events: [
                        (time: 0.0, intensity: 1.0, sharpness: 0.8),  // Strong hit
                        (time: 0.05, intensity: 0.6, sharpness: 0.5), // Quick follow
                        (time: 0.10, intensity: 0.8, sharpness: 0.7), // Medium
                        (time: 0.15, intensity: 0.4, sharpness: 0.3)  // Fade
                    ],
                    rhythm: .leftToRight  // Suggests left side
                )
            case .right:
                return HapticPattern(
                    events: [
                        (time: 0.0, intensity: 1.0, sharpness: 0.8),  // Strong hit
                        (time: 0.08, intensity: 0.7, sharpness: 0.6), // Delayed follow
                        (time: 0.15, intensity: 0.9, sharpness: 0.8), // Stronger
                        (time: 0.20, intensity: 0.5, sharpness: 0.4)  // Fade
                    ],
                    rhythm: .rightToLeft  // Suggests right side
                )
            case .top:
                return HapticPattern(
                    events: [
                        (time: 0.0, intensity: 1.0, sharpness: 0.9),  // Sharp hit
                        (time: 0.03, intensity: 0.5, sharpness: 0.4), // Quick drop
                        (time: 0.06, intensity: 0.8, sharpness: 0.7), // Rebound
                        (time: 0.10, intensity: 0.6, sharpness: 0.5), // Medium
                        (time: 0.15, intensity: 0.3, sharpness: 0.2)   // Fade
                    ],
                    rhythm: .topToBottom  // Suggests top edge
                )
            case .bottom:
                return HapticPattern(
                    events: [
                        (time: 0.0, intensity: 0.8, sharpness: 0.6),  // Medium start
                        (time: 0.05, intensity: 1.0, sharpness: 0.9), // Build up
                        (time: 0.10, intensity: 0.9, sharpness: 0.8), // Strong
                        (time: 0.15, intensity: 0.7, sharpness: 0.6), // Sustain
                        (time: 0.20, intensity: 0.4, sharpness: 0.3)  // Fade
                    ],
                    rhythm: .bottomToTop  // Suggests bottom edge
                )
            case .center:
                return HapticPattern(
                    events: [
                        (time: 0.0, intensity: 1.0, sharpness: 0.8),
                        (time: 0.05, intensity: 0.6, sharpness: 0.5),
                        (time: 0.10, intensity: 0.8, sharpness: 0.7),
                        (time: 0.15, intensity: 0.4, sharpness: 0.3)
                    ],
                    rhythm: .centered
                )
            }
        }
    }
    
    struct HapticPattern {
        struct Event {
            let time: TimeInterval
            let intensity: Float
            let sharpness: Float
        }
        
        enum Rhythm {
            case leftToRight, rightToLeft, topToBottom, bottomToTop, centered
        }
        
        let events: [(time: TimeInterval, intensity: Float, sharpness: Float)]
        let rhythm: Rhythm
    }
    
    private func triggerCoreHaptic(intensity: Float, direction: CollisionDirection, engine: CHHapticEngine) {
        let pattern = direction.hapticPattern
        
        // Scale intensity for all events
        let scaledEvents = pattern.events.map { event in
            (time: event.time,
             intensity: min(1.0, event.intensity * intensity),
             sharpness: event.sharpness)
        }
        
        var hapticEvents: [CHHapticEvent] = []
        
        // Create haptic events
        for event in scaledEvents {
            let hapticIntensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: event.intensity)
            let hapticSharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: event.sharpness)
            
            let hapticEvent = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [hapticIntensity, hapticSharpness],
                relativeTime: event.time
            )
            hapticEvents.append(hapticEvent)
        }
        
        // Add continuous haptic for rumble effect (optional - creates vibration)
        let continuousIntensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.3)
        let continuousSharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
        let continuousEvent = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [continuousIntensity, continuousSharpness],
            relativeTime: 0,
            duration: 0.2
        )
        hapticEvents.append(continuousEvent)
        
        do {
            let hapticPattern = try CHHapticPattern(events: hapticEvents, parameters: [])
            let player = try engine.makePlayer(with: hapticPattern)
            try player.start(atTime: 0)
            print("[Haptics] Core Haptic pattern played: \(direction)")
        } catch {
            print("[Haptics] Failed to play haptic pattern: \(error)")
            // Fall back to legacy
            triggerLegacyHaptic(intensity: intensity)
        }
    }
    
    private func triggerLegacyHaptic(intensity: Float) {
        // Game controller rumble: multiple rapid intense pulses
        let pulseCount = 4
        let pulseInterval: TimeInterval = 0.05

        // Initial strong hit
        notificationGenerator.notificationOccurred(.error)
        impactGenerator.impactOccurred(intensity: CGFloat(intensity))

        // Rapid follow-up pulses for rumble effect
        for i in 1..<pulseCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + pulseInterval * Double(i)) {
                self.impactGenerator.impactOccurred(intensity: CGFloat(intensity))
            }
        }

        // Final strong hit
        DispatchQueue.main.asyncAfter(deadline: .now() + pulseInterval * Double(pulseCount)) {
            self.notificationGenerator.notificationOccurred(.error)
            self.impactGenerator.impactOccurred(intensity: CGFloat(intensity))
        }
    }
}

// MARK: - NISessionDelegate

extension BumperSession: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let object = nearbyObjects.first else { return }

        let newDistance = object.distance
        let newDirection = object.direction

        // Debug: Log what NI is providing with more detail
        print("[NI] ============ UPDATE ============")
        print("[NI] Distance: \(newDistance?.description ?? "nil")")
        print("[NI] Direction: \(newDirection?.debugDescription ?? "nil")")
        
        // Check if direction is actually available (even if capability says false)
        if let dir = newDirection {
            lastKnownDirection = dir
            print("[NI] ✅ Got direction: x=\(String(format: "%.3f", dir.x)) y=\(String(format: "%.3f", dir.y)) z=\(String(format: "%.3f", dir.z))")
            print("[NI] Direction magnitude: \(String(format: "%.3f", sqrt(dir.x*dir.x + dir.y*dir.y + dir.z*dir.z)))")
        } else {
            print("[NI] ❌ Direction is nil")
            print("[NI] This could be because:")
            print("[NI]   1. Capability check returned false (but might still work)")
            print("[NI]   2. Phones too close (<10cm) or too far (>9m)")
            print("[NI]   3. Phones not in proper orientation (need to be upright)")
            print("[NI]   4. Missing entitlement (check Apple Developer Portal)")
            print("[NI]   5. UWB hardware issue")
        }
        
        // Log session state
        if #available(iOS 16.0, *) {
            print("[NI] Session supportsDirection: \(NISession.deviceCapabilities.supportsDirectionMeasurement)")
        }
        print("[NI] ===============================")

        DispatchQueue.main.async {
            self.distance = newDistance
            if let dir = newDirection {
                self.direction = dir
            }

            // Debug: show distance, threshold, direction status
            if let dist = newDistance {
                let dirForThreshold = newDirection ?? self.lastKnownDirection
                let threshold = self.phoneGeometry.collisionThreshold(for: dirForThreshold)
                let peerName = self.connectedPeer?.displayName ?? "?"
                let dirStatus: String
                if let dir = newDirection {
                    dirStatus = String(format: "x=%.1f y=%.1f", dir.x, dir.y)
                } else if self.lastKnownDirection != nil {
                    dirStatus = "using last"
                } else {
                    dirStatus = "no dir"
                }
                self.debugLog = String(format: "%@ → %@\nDist: %.0fcm Thr: %.0fcm [%@]",
                    self.myPeerID.displayName, peerName, dist * 100, threshold * 100, dirStatus)
                
                // Update detailed debug with direction info
                if let dir = newDirection {
                    self.debugDetails += "\n\nDirection: x=\(String(format: "%.2f", dir.x)) y=\(String(format: "%.2f", dir.y)) z=\(String(format: "%.2f", dir.z))"
                } else {
                    self.debugDetails += "\n\nDirection: ❌ nil"
                }
            }
        }

        // Process for collision detection - use last known direction if current is nil
        if let dist = newDistance {
            processDistanceUpdate(dist, direction: newDirection ?? lastKnownDirection)
        }
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        print("[NI] Peer removed: \(reason)")

        DispatchQueue.main.async {
            self.distance = nil
            self.direction = nil
        }

        // If removed due to timeout, try to restart
        if reason == .timeout {
            if let token = session.discoveryToken {
                sendDiscoveryToken(token)
            }
        }
    }

    func sessionWasSuspended(_ session: NISession) {
        print("[NI] Session suspended")
    }

    func sessionSuspensionEnded(_ session: NISession) {
        print("[NI] Session suspension ended")
        // Restart the session
        if let token = session.discoveryToken {
            sendDiscoveryToken(token)
        }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        print("[NI] Session invalidated: \(error)")

        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionStatus = .searching
        }

        // Try to recreate session
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if self.connectedPeer != nil {
                self.setupNearbyInteraction()
            }
        }
    }
}

// MARK: - MCSessionDelegate

extension BumperSession: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let stateStr = state == .connected ? "CONNECTED" : state == .connecting ? "connecting" : "not connected"
        log("Peer \(peerID.displayName): \(stateStr)")

        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.connectedPeer = peerID
                self.peersFound = session.connectedPeers.count
                self.log("Starting Nearby Interaction...")
                self.setupNearbyInteraction()

            case .notConnected:
                if self.connectedPeer == peerID {
                    self.connectedPeer = nil
                    self.isConnected = false
                    self.connectionStatus = .searching
                    self.niSession?.invalidate()
                    self.niSession = nil
                }
                self.peersFound = session.connectedPeers.count

            case .connecting:
                break

            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        print("[MC] Received \(data.count) bytes from \(peerID.displayName)")
        handleReceivedToken(data)
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used
    }

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension BumperSession: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("[MC] Received invitation from \(peerID.displayName)")

        // Auto-accept invitations
        invitationHandler(true, mcSession)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("[MC] Failed to advertise: \(error)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension BumperSession: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        log("Found peer: \(peerID.displayName) (I am: \(myPeerID.displayName))")

        DispatchQueue.main.async {
            self.peersFound += 1
        }

        // Invite if we don't have a connection yet
        guard connectedPeer == nil else {
            log("Already connected, ignoring peer")
            return
        }

        log("Inviting peer: \(peerID.displayName)")
        browser.invitePeer(peerID, to: mcSession!, withContext: nil, timeout: 30)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("[MC] Lost peer: \(peerID.displayName)")

        DispatchQueue.main.async {
            self.peersFound = max(0, self.peersFound - 1)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("[MC] Failed to browse: \(error)")
    }
}

// MARK: - Phone Geometry

struct PhoneGeometry {
    let height: Float      // Phone height in meters
    let width: Float       // Phone width in meters
    let chipFromTop: Float // Distance from top edge to UWB chip in meters

    // Distance from chip to each edge
    var chipToTop: Float { chipFromTop }
    var chipToBottom: Float { height - chipFromTop }
    var chipToSide: Float { width / 2 }

    // Expected chip-to-chip distance when edges touch
    func collisionThreshold(for direction: simd_float3?) -> Float {
        guard let dir = direction else {
            // No direction available - use moderate average threshold
            return 0.15
        }

        // For phones lying FLAT (screen up):
        // x = left/right, y = toward top/bottom of phone, z = up into air
        let absX = abs(dir.x)
        let absY = abs(dir.y)

        // Determine primary collision edge based on direction
        if absY > absX {
            if dir.y > 0 {
                // Top edge (notch side) - UWB chip is close to this edge
                return chipToTop * 2 + 0.05
            } else {
                // Bottom edge (charging port) - needs more buffer
                // TODO: Calibrate this better - seeing ~50cm for iPhone 12 + 16
                return chipToBottom * 2 + 0.25
            }
        } else {
            // Side edge - accurate, minimal buffer
            return chipToSide * 2 + 0.03
        }
    }

    static func current() -> PhoneGeometry {
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        } ?? "Unknown"

        // iPhone dimensions in meters (height x width)
        // UWB chip is roughly 15-20mm from top edge in most models
        switch modelCode {
        // iPhone 11 series
        case _ where modelCode.hasPrefix("iPhone12"):
            return PhoneGeometry(height: 0.1509, width: 0.0756, chipFromTop: 0.018)

        // iPhone 12 series
        case _ where modelCode.hasPrefix("iPhone13"):
            return PhoneGeometry(height: 0.1464, width: 0.0715, chipFromTop: 0.017)

        // iPhone 13 series
        case _ where modelCode.hasPrefix("iPhone14"):
            return PhoneGeometry(height: 0.1465, width: 0.0715, chipFromTop: 0.017)

        // iPhone 14 series
        case _ where modelCode.hasPrefix("iPhone15"):
            return PhoneGeometry(height: 0.1475, width: 0.0715, chipFromTop: 0.017)

        // iPhone 15 series
        case _ where modelCode.hasPrefix("iPhone16"):
            return PhoneGeometry(height: 0.1477, width: 0.0715, chipFromTop: 0.017)

        // iPhone 16 series
        case _ where modelCode.hasPrefix("iPhone17"):
            return PhoneGeometry(height: 0.1477, width: 0.0715, chipFromTop: 0.017)

        default:
            // Default to iPhone 14-ish dimensions
            return PhoneGeometry(height: 0.1475, width: 0.0715, chipFromTop: 0.017)
        }
    }
}
