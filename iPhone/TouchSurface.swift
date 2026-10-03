import SwiftUI
import UIKit

struct TouchSurface: UIViewRepresentable {
    var scrolling = false
    var dragLocked = false
    var dualHand: Bool
    var settings: TrackpadSettings
    var sensitivity: Double
    var haptics: Bool
    var enabled: Bool
    var send: (InputEvent) -> Void
    func makeUIView(context: Context) -> PadView { PadView() }
    func updateUIView(_ view: PadView, context: Context) {
        if view.engine.dragLocked != dragLocked || view.engine.split != dualHand || view.engine.scrolling != scrolling { view.cancelGesture() }
        view.engine.settings=settings
        view.engine.scrolling=scrolling
        view.engine.dragLocked=dragLocked
        view.engine.split=dualHand
        view.engine.sensitivity=sensitivity
        view.haptics=haptics; view.send=send
        view.accessibilityLabel=dualHand ? "双手触摸区" : "触摸区"
        view.accessibilityHint="单指移动，双指滚动、缩放或旋转；多指手势跟随 Mac 设置。"
        view.isUserInteractionEnabled=enabled
        if !enabled { view.cancelGesture() }
    }
}

final class PadView: UIView {
    let engine=PadGestures()
    var haptics=true
    var send: (InputEvent)->Void = { _ in }
    private var fingers: [ObjectIdentifier:(Int,UITouch)] = [:]
    private var nextID=0
    private var hold: Timer?
    private var heartbeat: Timer?
    private let feedback=UIImpactFeedbackGenerator(style:.light)
    override init(frame: CGRect) {
        super.init(frame:frame)
        isMultipleTouchEnabled=true; backgroundColor = .clear
        isAccessibilityElement=true; accessibilityTraits=[.allowsDirectInteraction]
        engine.emit = { [weak self] event in
            guard let self else { return }
            self.send(event)
            if event.kind == "tap" || event.kind == "system" || event.kind == "drag" {
                if self.haptics { self.feedback.impactOccurred(intensity:0.6) }
            }
            if event.kind == "drag" {
                self.heartbeat?.invalidate()
                if event.action == "begin" {
                    let timer=Timer(timeInterval:1,repeats:true) { [weak self] _ in self?.send(InputEvent(kind:"hold")) }
                    self.heartbeat=timer; RunLoop.main.add(timer,forMode:.common)
                }
            }
        }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func frame(time:Double) {
        engine.size=bounds.size
        engine.update(fingers.values.map { id,touch in
            let p=touch.location(in:self); return Contact(id:id,x:p.x,y:p.y)
        },time:time)
    }
    override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent?) {
        let empty=fingers.isEmpty
        for touch in touches {
            let p=touch.location(in:self)
            if engine.split && p.x >= bounds.width*0.30 && p.x <= bounds.width*0.70 { continue }
            nextID += 1; fingers[ObjectIdentifier(touch)]=(nextID,touch)
        }
        frame(time:event?.timestamp ?? ProcessInfo.processInfo.systemUptime)
        hold?.invalidate()
        if empty && fingers.count == 1 {
            feedback.prepare()
            let timer=Timer(timeInterval:0.4,repeats:false) { [weak self] _ in self?.engine.longPress() }
            hold=timer; RunLoop.main.add(timer,forMode:.common)
        }
    }
    override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent?) {
        // Preserve hardware samples and their time intervals, without waiting for a display frame.
        if fingers.count == 1, let touch=touches.first, let (id,_)=fingers[ObjectIdentifier(touch)],
           let samples=event?.coalescedTouches(for:touch), !samples.isEmpty {
            engine.size=bounds.size
            for sample in samples {
                let p=sample.location(in:self)
                engine.update([Contact(id:id,x:p.x,y:p.y)],time:sample.timestamp)
            }
        } else { frame(time:event?.timestamp ?? ProcessInfo.processInfo.systemUptime) }
    }
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent?) {
        // Process final coordinates before lifting, so a quick swipe cannot become a tap.
        frame(time:event?.timestamp ?? ProcessInfo.processInfo.systemUptime)
        for touch in touches { fingers.removeValue(forKey:ObjectIdentifier(touch)) }
        hold?.invalidate(); frame(time:event?.timestamp ?? ProcessInfo.processInfo.systemUptime)
    }
    override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent?) { cancelGesture() }
    func cancelGesture() { hold?.invalidate(); engine.cancel(); fingers.removeAll(); heartbeat?.invalidate() }
    override func didMoveToWindow() { if window == nil { cancelGesture() } }
    override var editingInteractionConfiguration: UIEditingInteractionConfiguration { .none }
}
