iPhone Bumper Car Prototype - Project Plan
Requirements

2x iPhone 11 or newer (UWB support)
2x RC car bases
Xcode + Apple Developer account
Phone mounts for RC cars

Phase 1: Core NI Setup (Day 1-2)
1.1 Project scaffolding

Create new iOS app (SwiftUI)
Add Nearby Interaction + MultipeerConnectivity frameworks
Request motion & NI permissions in Info.plist

1.2 Device discovery

Implement MultipeerConnectivity session
Auto-discover nearby devices running app
Exchange NI tokens between devices

1.3 Distance tracking

Start NI session with exchanged tokens
Display live distance between phones on screen
Log distance values to verify accuracy

Phase 2: Collision Detection (Day 3)
2.1 Impact algorithm

Monitor distance deltas (rate of change)
Detect collision pattern: rapid approach → sudden stop/spike
Threshold tuning (test by hand-bumping phones)

2.2 Direction calculation

Use NI's direction vector to determine impact angle
Convert to screen coordinates (top/bottom/left/right)
Account for phone orientation

Phase 3: Interaction Response (Day 4)
3.1 Haptic feedback

Trigger UIImpactFeedbackGenerator on collision
Match intensity to collision force

3.2 Visual indicator

Draw red circle overlay at impact position
Calculate circle position from direction vector
Animate: appear → fade out (0.5s duration)

3.3 Testing

Test with phones in hand
Verify direction accuracy matches actual bump angle
Tune haptic intensity and circle size

Phase 4: RC Integration (Day 5)
4.1 Physical mounting

Secure phones to RC cars (screen facing up)
Ensure phones don't shift during collisions
Test Bluetooth range for RC control

4.2 Calibration

Test collision detection at RC speeds
Adjust thresholds for harder impacts
Verify circle position accuracy while moving

Deliverables

Working iOS app that pairs 2 phones
Haptic + visual feedback on collision
Demo video of RC bumper cars

Future Work

Multi-phone support: Extend to support 3+ phones simultaneously (refactor connectedPeer to array, run multiple NI sessions)

Bottom-to-bottom calibration: Current threshold (~51cm) works but needs tuning. iPhone 12 + iPhone 16 bottom-to-bottom shows ~50cm measured distance. May need per-model calibration or dynamic threshold learning.


