import Foundation
import CoreGraphics

struct TrackpadSettings: Codable, Equatable {
    var tapToClick = true
    var secondaryClick = true
    var secondaryCorner = 0
    var naturalScroll = true
    var scroll = true
    var horizontalScroll = true
    var momentum = true
    var pinch = true
    var rotate = true
    var smartZoom = true
    var threeFingerDrag = false
    var tapDragging = false
    var dragLock = false
    var lookup = false
    var threeFingerHorizontal = false
    var threeFingerPages = false
    var threeFingerVertical = true
    var fourFingerHorizontal = true
    var fourFingerVertical = true
    var fourFingerPinch = true
    var notificationCenter = true
    var trackingSpeed = 1.0
    var doubleClickInterval = 0.3
    var nativeAcceleration: Bool? = nil
    var continuousDock: Bool? = nil
}

struct Contact {
    var id: Int
    var x: Double
    var y: Double
}

enum Motion {
    static func dualIntent(spread: Double, translation: Double) -> String {
        if spread > 8 && spread > translation * 1.4 { return "zoom" }
        if translation > 8 { return "move" }
        return "pending"
    }
    static func angleDelta(_ value: Double) -> Double { atan2(sin(value), cos(value)) }
}

// One recognizer for both orientations. Contact-count changes rebase without cursor jumps.
final class PadGestures {
    var settings = TrackpadSettings()
    var split = false
    var dragLocked = false
    var scrolling = false
    var sensitivity = 1.0
    var size = CGSize(width: 400, height: 600)
    var emit: (InputEvent) -> Void = { _ in }
    private var previous: [Contact] = []
    private var origins: [Int: Contact] = [:]
    private var baseline: [Contact] = []
    private var began = 0.0
    private var previousTime = 0.0
    private var maximumCount = 0
    private var travel = 0.0
    private var intent = "pending"
    private var moved = false
    private var endedCohort = false
    private var autoDrag = false
    private var tapDrag = false
    private var heldAcrossLift = false
    private var swipeProgress = 0.0
    private var swipeVelocity = 0.0
    private var lastSwipeMotion = 0.0
    private var velocity = CGPoint.zero
    private var lastMotionTime = 0.0
    private var lastTap = -100.0
    private var activeTransform = Set<String>()

    private func center(_ p: [Contact]) -> CGPoint {
        guard !p.isEmpty else { return .zero }
        return CGPoint(x: p.map(\.x).reduce(0,+) / Double(p.count), y: p.map(\.y).reduce(0,+) / Double(p.count))
    }
    private func radius(_ p: [Contact]) -> Double {
        let c = center(p)
        return p.map { hypot($0.x - c.x, $0.y - c.y) }.reduce(0,+) / Double(max(1,p.count))
    }
    private func angle(_ p: [Contact]) -> Double { p.count == 2 ? atan2(p[1].y-p[0].y,p[1].x-p[0].x) : 0 }
    private func output(_ kind: String, _ action: String = "", _ x: Double = 0, _ y: Double = 0) {
        emit(InputEvent(kind: kind, x: x, y: y, action: action))
    }
    private func move(_ dx: Double, _ dy: Double, dt: Double) {
        guard dx != 0 || dy != 0 else { return }
        emit(InputEvent(kind: "pointer", x: dx*sensitivity, y: dy*sensitivity, dt: dt))
    }
    private func beginDrag(tap: Bool = false) {
        guard !autoDrag, !dragLocked else { return }
        autoDrag = true; tapDrag = tap; moved = true
        output("drag", "begin")
    }
    func longPress() {
        guard previous.count == 1, maximumCount == 1, travel < 7, !scrolling, !dragLocked else { return }
        beginDrag()
    }
    func cancel() {
        finish(cancelled: true, time: previousTime)
        previous = []; origins = [:]; baseline = []; maximumCount = 0
    }
    private func finish(cancelled: Bool, time: Double, retainDrag: Bool = false) {
        let end = cancelled ? "cancel" : "end"
        if intent == "scroll" { output("scroll", end)
            if !cancelled && settings.momentum && time-lastMotionTime < 0.1 && hypot(velocity.x,velocity.y) > 80 {
                output("inertia", "", velocity.x, velocity.y)
            }
        }
        for kind in activeTransform.sorted() { output(kind, end) }
        activeTransform.removeAll()
        if intent == "swipeX" || intent == "swipeY" {
            emit(InputEvent(kind: "dock", x: swipeProgress, y: intent == "swipeX" ? 1 : 2, action: end,
                            velocity: !cancelled && time-lastSwipeMotion < 0.08 ? swipeVelocity : 0))
        }
        if autoDrag && !retainDrag { output("drag", "end"); autoDrag = false; tapDrag = false; heldAcrossLift = false }
        intent = "pending"; velocity = .zero; swipeProgress = 0; swipeVelocity = 0
    }
    func update(_ contacts: [Contact], time: Double) {
        let p = contacts.sorted { $0.id < $1.id }
        if previous.isEmpty && !p.isEmpty {
            began = time; maximumCount = 0; travel = 0; moved = false; endedCohort = false
            origins = [:]; output("gesture", "begin")
            if p.count == 1, settings.tapDragging, time-lastTap < settings.doubleClickInterval { beginDrag(tap: true) }
        }
        for finger in p {
            if origins[finger.id] == nil { origins[finger.id] = finger }
            let origin = origins[finger.id]!
            travel = max(travel,hypot(finger.x-origin.x,finger.y-origin.y))
        }
        if p.isEmpty {
            let canTap = !moved && !autoDrag && travel < 7 && time-began < 0.35
            let retainDrag = autoDrag && tapDrag && settings.dragLock && (!heldAcrossLift || travel > 7)
            finish(cancelled: false, time: time, retainDrag: retainDrag)
            heldAcrossLift = retainDrag
            if canTap && !scrolling && !dragLocked {
                let c=center(previous)
                output("tap", c.y > size.height*0.85 ? "bottom" : "", Double(maximumCount), c.x / max(1,size.width))
                if maximumCount == 1 { lastTap=time }
            }
            previous=[]; origins=[:]; baseline=[]; maximumCount=0
            return
        }
        let countChanged = p.map(\.id) != previous.map(\.id)
        if countChanged {
            if !previous.isEmpty {
                let wasDrag = autoDrag && p.count == 1 && previous.count == 1
                if !wasDrag { finish(cancelled: p.count > previous.count, time: time) }
                if p.count < previous.count { endedCohort = true }
            }
            maximumCount=max(maximumCount,p.count)
            baseline=p; previous=p; previousTime=time
            return
        }
        let c=center(p), old=center(previous), start=center(baseline)
        let dx=c.x-old.x, dy=c.y-old.y
        let tx=c.x-start.x, ty=c.y-start.y
        let dt=max(0.001,min(0.25,time-previousTime))
        defer { previous=p; previousTime=time }
        if endedCohort && !split { return }
        if dragLocked || autoDrag || p.count == 1 && !scrolling {
            move(dx,dy,dt:dt)
            if travel > 7 { moved=true }
            return
        }
        if p.count == 3 && settings.threeFingerDrag && !scrolling {
            if travel > 3 { beginDrag(); move(dx,dy,dt:dt) }
            return
        }
        let r=radius(p), initialRadius=max(1,radius(baseline))
        let spread=r-initialRadius
        if p.count >= 4 && settings.fourFingerPinch && intent == "pending" && abs(spread) > 18 && abs(spread) > hypot(tx,ty)*0.8 {
            output("system",spread > 0 ? "desktop" : "applications")
            intent="consumed"; moved=true
        }
        if intent == "consumed" { return }
        if p.count >= 3 {
            if p.count == 3 && settings.threeFingerPages && intent == "pending" && abs(tx)>35 && abs(tx)>abs(ty)*1.5 {
                output("page","",tx); intent="consumed"; moved=true; return
            }
            let horizontal=p.count == 3 ? settings.threeFingerHorizontal : settings.fourFingerHorizontal
            let vertical=p.count == 3 ? settings.threeFingerVertical : settings.fourFingerVertical
            if intent == "pending" && hypot(tx,ty)>12 {
                if abs(tx)>abs(ty)*1.2 && horizontal { intent="swipeX" }
                else if abs(ty)>abs(tx)*1.2 && vertical { intent="swipeY" }
                if intent != "pending" {
                    moved=true
                    output("dock","begin",(intent == "swipeX" ? tx : ty)/180,intent == "swipeX" ? 1 : 2)
                }
            }
            if intent == "swipeX" || intent == "swipeY" {
                swipeProgress = max(-1.5,min(1.5,(intent == "swipeX" ? tx : ty)/180))
                let delta = intent == "swipeX" ? dx : dy
                if delta != 0 {
                    swipeVelocity = 0.3*swipeVelocity + 0.7*delta/dt/180
                    lastSwipeMotion=time
                }
                output("dock","change",swipeProgress,intent == "swipeX" ? 1 : 2)
            }
            return
        }
        let crosses = split && p.count == 2 && p[0].x < size.width*0.30 && p[1].x > size.width*0.70 || split && p.count == 2 && p[1].x < size.width*0.30 && p[0].x > size.width*0.70
        let rotation=Motion.angleDelta(angle(p)-angle(baseline))
        if intent == "pending" {
            let pinchScore = settings.pinch ? abs(log(max(1,r)/initialRadius))/0.045 : 0
            let rotateScore = settings.rotate ? abs(rotation)/0.09 : 0
            if !scrolling && p.count == 2 && max(pinchScore,rotateScore)>1 && max(pinchScore,rotateScore)>hypot(tx,ty)/7 { intent="transform" }
            else if hypot(tx,ty)>5 && (settings.scroll || crosses || scrolling) {
                let fromRight = p.count == 2 && baseline.allSatisfy { $0.x > size.width * 0.85 }
                if fromRight && settings.notificationCenter && tx < 0 && abs(tx)>abs(ty)*2 {
                    if tx > -18 { return }
                    output("system","notifications"); intent="consumed"; moved=true; return
                }
                intent=crosses && !scrolling ? "move" : "scroll"
                if intent == "scroll" { output("scroll","begin") }
            }
            if intent != "pending" { moved=true }
        }
        if intent == "move" { move(dx,dy,dt:dt) }
        if intent == "scroll" && hypot(dx,dy)>0 {
            let sx=settings.horizontalScroll ? dx*2 : 0, sy=dy*2
            velocity=CGPoint(x: velocity.x*0.65+sx/dt*0.35,y:velocity.y*0.65+sy/dt*0.35)
            lastMotionTime=time
            output("scroll","change",sx,sy)
        }
        if intent == "transform" {
            if settings.pinch {
                if !activeTransform.contains("magnify") { activeTransform.insert("magnify"); output("magnify","begin") }
                output("magnify","change",r/max(1,radius(previous))-1)
            }
            if settings.rotate {
                if !activeTransform.contains("rotate") { activeTransform.insert("rotate"); output("rotate","begin") }
                output("rotate","change",-Motion.angleDelta(angle(p)-angle(previous))*180 / .pi)
            }
        }
    }
}
