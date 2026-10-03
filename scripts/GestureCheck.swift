import Foundation
import AppKit

@main struct GestureCheck {
    static func main() {
        var events=[InputEvent]()
        let g=PadGestures(); g.emit={events.append($0)}
        func frame(_ p:[(Double,Double)],_ t:Double) { g.update(p.enumerated().map { Contact(id:$0.offset,x:$0.element.0,y:$0.element.1) },time:t) }
        frame([(100,100)],0); frame([(105,103)],0.01); frame([],0.05)
        precondition(events.contains {$0.kind == "pointer"})
        precondition(events.filter {$0.kind == "tap"}.count == 1)
        events=[]
        frame([(100,100),(150,100)],1); frame([(100,120),(150,120)],1.02); frame([(100,140),(150,140)],1.04); frame([],1.05)
        precondition(events.filter {$0.kind == "scroll"}.map(\.action) == ["begin","change","change","end"])
        precondition(events.contains {$0.kind == "inertia"})
        precondition(!events.contains {$0.kind == "tap"})
        events=[]
        frame([(100,100),(150,100)],2); frame([(80,100),(170,100)],2.02); frame([],2.04)
        precondition(events.contains {$0.kind == "magnify" && $0.x>0})
        precondition(!events.contains {$0.kind == "tap" || $0.kind == "scroll"})
        events=[]; g.settings.threeFingerDrag=true
        frame([(100,100),(120,100),(140,100)],3); frame([(110,100),(130,100),(150,100)],3.02); frame([],3.04)
        precondition(events.filter {$0.kind == "drag"}.map(\.action) == ["begin","end"])
        precondition(!events.contains {$0.kind == "dock"})
        events=[]; g.dragLocked=true
        frame([(100,100)],4); frame([(140,100)],4.02); frame([],4.04); frame([(20,100)],4.1); frame([(40,100)],4.12); frame([],4.14)
        precondition(events.filter {$0.kind == "pointer"}.count == 2)
        precondition(!events.contains {$0.kind == "drag" || $0.kind == "tap"})
        events=[]; g.dragLocked=false
        frame([(100,100),(120,100),(140,100),(160,100)],5); frame([(100,70),(120,70),(140,70),(160,70)],5.02); frame([],5.04)
        precondition(events.filter {$0.kind == "dock"}.map(\.action) == ["begin","change","end"])
        events=[]; g.split=true; g.size=CGSize(width:800,height:400)
        frame([(100,200),(700,200)],6); frame([(115,200),(715,200)],6.02); frame([],6.04)
        precondition(events.contains {$0.kind == "pointer"})
        precondition(!events.contains {$0.kind == "scroll"})
        events=[]; g.split=false; g.settings.tapDragging=true; g.settings.dragLock=true
        frame([(100,100)],7); frame([],7.02)
        frame([(100,100)],7.1); frame([(150,100)],7.12); frame([],7.14)
        precondition(events.filter {$0.kind == "drag" && $0.action == "end"}.isEmpty)
        frame([(100,100)],7.6); frame([],7.62)
        precondition(events.filter {$0.kind == "drag"}.map(\.action) == ["begin","end"])
        events=[]; g.settings.tapDragging=false
        frame([(100,100),(150,100)],8); frame([(100,120),(150,120)],8.02); frame([(100,140),(150,140)],8.04)
        frame([(100,140),(150,140)],8.5); frame([],8.51)
        precondition(!events.contains {$0.kind == "inertia"})
        events=[]
        frame([(100,100),(150,100)],9); frame([(100,120),(150,120)],9.02); frame([(100,120)],9.04); frame([],9.05)
        precondition(events.filter {$0.kind == "scroll"}.last?.action == "end")
        precondition(!events.contains {$0.kind == "tap"})
        for (kind,type,value) in [("magnify",NSEvent.EventType.magnify,0.1),("rotate",.rotate,15.0),("smartZoom",.smartMagnify,0.0)] {
            guard let e=NativeGesture.make(kind,action:"change",value:value),let n=NSEvent(cgEvent:e) else { fatalError("Cannot decode \(kind)") }
            precondition(n.type == type)
            precondition(n.phase == .changed)
            if type == .magnify { precondition(abs(n.magnification-value)<0.0001) }
            if type == .rotate { precondition(abs(Double(n.rotation)-value)<0.0001) }
        }
        // Reversal and a paused release must carry the right terminal velocity.
        events=[]
        func four(_ x:Double,_ time:Double) { frame([(x,100),(x+20,100),(x+40,100),(x+60,100)],time) }
        four(100,10); four(160,10.1); four(140,10.2); frame([],10.21)
        precondition((events.last(where: {$0.kind == "dock"})?.velocity ?? 1) < 0)
        events=[]; four(100,11); four(160,11.1); four(160,11.5); frame([],11.51)
        precondition(events.last(where: {$0.kind == "dock"})?.velocity == 0)
        events=[]; four(100,12); four(160,12.1); g.cancel()
        precondition(events.last?.action == "cancel")
        for axis in [1,2] { for action in ["begin","change","end","cancel"] {
            guard let e=NativeGesture.dock(action:action,progress:-0.25,axis:axis,velocity:-0.3) else { fatalError("HID bridge unavailable") }
            if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
                precondition(TPCheckDockPayload(e,Int32(NativeGesture.phase(action)),Int32(axis),axis == 1 ? -0.25 : 0.25,axis == 1 ? -0.3 : 0.3))
            }
        } }
        let screens=[CGRect(x:0,y:0,width:1440,height:900),CGRect(x:-1920,y:-180,width:1920,height:1080),CGRect(x:0,y:-1080,width:1920,height:1080)]
        for point in [CGPoint(x:-40,y:300),CGPoint(x:1400,y:-40)] { precondition(DesktopBounds.constrain(point,to:screens)==point) }
        precondition(DesktopBounds.constrain(CGPoint(x:2000,y:100),from:CGPoint(x:1400,y:100),to:screens).x < 1440)
        let acceleration=PointerAcceleration()
        precondition(acceleration.available,"Current Mac should expose its trackpad curve")
        let slow=acceleration.apply(x:1,y:0,dt:1/60).x
        let fast=acceleration.apply(x:10,y:0,dt:1/60).x/10
        precondition(fast>slow)
        let at60=acceleration.apply(x:10,y:0,dt:1/60).x
        let at120=acceleration.apply(x:5,y:0,dt:1/120).x*2
        precondition(abs(at60-at120)<0.0001)
        acceleration.refresh(index:0)
        precondition(acceleration.apply(x:10,y:0,dt:1/60).x < at60)
        acceleration.refresh(index:-1)
        precondition(!acceleration.available && acceleration.apply(x:10,y:0,dt:1/60).x == 10)
        print("PASS: native curve (slow gain \(slow), fast gain \(fast)), 60/120 Hz invariance, speed changes, desktop topology, Dock HID payloads, reversal/cancel")
        let p=MacTrackpadPreferences.read()
        print("PASS: gesture phases, tap rejection, pinch, three-finger drag, persistent manual drag, four-finger swipe, split-pad movement, AppKit event decoding")
        print("System preferences read: threeFingerDrag=\(p.threeFingerDrag), fourFingerHorizontal=\(p.fourFingerHorizontal)")
    }
}
