import AppKit

// Preference keys are not a public Apple API. Read only; never rewrite the user's settings.
enum MacTrackpadPreferences {
    static func read() -> TrackpadSettings {
        let domain="com.apple.AppleMultitouchTrackpad" as CFString
        let bluetooth="com.apple.driver.AppleBluetoothMultitouch.trackpad" as CFString
        CFPreferencesAppSynchronize(domain); CFPreferencesAppSynchronize(bluetooth)
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        func value(_ key:String, domain:CFString) -> NSNumber? {
            (CFPreferencesCopyValue(key as CFString,domain,kCFPreferencesCurrentUser,kCFPreferencesCurrentHost)
             ?? CFPreferencesCopyValue(key as CFString,domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost)) as? NSNumber
        }
        func number(_ key:String,_ fallback:Int) -> Int { (value(key,domain:domain) ?? value(key,domain:bluetooth))?.intValue ?? fallback }
        func flag(_ key:String,_ fallback:Bool=true) -> Bool { number(key,fallback ? 1 : 0) != 0 }
        var p=TrackpadSettings()
        p.tapToClick=flag("Clicking")
        p.secondaryClick=flag("TrackpadRightClick")
        p.secondaryCorner=number("TrackpadCornerSecondaryClick",0)
        p.naturalScroll=value("com.apple.swipescrolldirection",domain:kCFPreferencesAnyApplication)?.boolValue ?? true
        p.scroll=flag("TrackpadScroll"); p.horizontalScroll=flag("TrackpadHorizScroll")
        p.momentum=flag("TrackpadMomentumScroll"); p.pinch=flag("TrackpadPinch"); p.rotate=flag("TrackpadRotate")
        p.smartZoom=flag("TrackpadTwoFingerDoubleTapGesture")
        p.threeFingerDrag=flag("TrackpadThreeFingerDrag",false)
        p.tapDragging=flag("Dragging",false); p.dragLock=flag("DragLock",false)
        p.lookup=flag("TrackpadThreeFingerTapGesture",false)
        p.threeFingerHorizontal=number("TrackpadThreeFingerHorizSwipeGesture",0)==2
        p.threeFingerPages=number("TrackpadThreeFingerHorizSwipeGesture",0)==1
        p.threeFingerVertical=flag("TrackpadThreeFingerVertSwipeGesture",!p.threeFingerDrag)
        p.fourFingerHorizontal=flag("TrackpadFourFingerHorizSwipeGesture")
        p.fourFingerVertical=flag("TrackpadFourFingerVertSwipeGesture")
        p.fourFingerPinch=flag("TrackpadFourFingerPinchGesture")
        p.notificationCenter=flag("TrackpadTwoFingerFromRightEdgeSwipeGesture")
        let speed=value("com.apple.trackpad.scaling",domain:kCFPreferencesAnyApplication)?.doubleValue ?? 1
        p.trackingSpeed=max(-1,min(3,speed))
        p.doubleClickInterval=NSEvent.doubleClickInterval
        return p
    }
}

// Compatibility bridge, not a registered hardware trackpad. Private event fields can change.
// Gesture serialization adapted from scottlamb/macos-trackpad-companion (MIT),
// based on calftrail/Touch. Field definitions also appear in WebKit CoreGraphicsTestSPI.h.
// See docs/ThirdPartyNotices.txt and docs/Gestures.md.
enum NativeGesture {
    static func phase(_ action:String) -> Int64 { ["begin":1,"change":2,"end":4,"cancel":8][action] ?? 2 }
    static func make(_ kind:String, action:String, value:Double=0) -> CGEvent? {
        guard let proto=CGEvent(source:nil) else { return nil }
        proto.type=CGEventType(rawValue:29)!
        proto.flags=CGEventFlags(rawValue:0x100)
        guard let raw=proto.data, CFDataGetLength(raw)>24 else { return nil }
        var data=Data(raw as Data).dropLast(24)
        func append<T>(_ value:T) { var v=value; withUnsafeBytes(of:&v) { data.append(contentsOf:$0) } }
        func field(_ id:UInt8,_ value:UInt32,_ floating:Bool=false) {
            append(UInt16(1).bigEndian); append(UInt8(floating ? 0xC0 : 0x40)); append(id); append(value.bigEndian)
        }
        // IOHID queue (24), digitizer hand (96), vendor token (32 + 40).
        append(UInt16(192).bigEndian); append(UInt8(0x10)); append(UInt8(0x6D))
        let timestamp=proto.timestamp
        append(timestamp); append(UInt64(0)); append(UInt32(2)); append(UInt32(2))
        append(UInt32(96)); append(UInt32(11)); append(timestamp)
        let hand:[UInt32]=[2,0,0,0,0,0x23,0,0,0,0,0,0,0,2,0,0,0,0,0,0]
        for v in hand { append(v) }
        append(UInt32(72)); append(UInt32(1)); append(timestamp); append(UInt32(0))
        append(UInt16(0xFF00)); append(UInt16(0x1777)); append(UInt32(1)); append(UInt32(40))
        data.append(contentsOf:repeatElement(UInt8(0),count:40))
        let subtype:UInt32 = kind == "rotate" ? 5 : kind == "smartZoom" ? 22 : kind == "swipe" ? 16 : 8
        field(110,subtype); field(111,0); field(112,0); field(132,UInt32(phase(action))); field(133,0)
        if kind == "swipe" { field(115,UInt32(value)) }
        else if kind != "smartZoom" { field(kind == "rotate" ? 114 : 113,Float(value).bitPattern,true) }
        field(139,0,true); field(140,0,true)
        guard let result=CGEvent(withDataAllocator:nil, data:Data(data) as CFData), let decoded=NSEvent(cgEvent:result) else { return nil }
        let expected:NSEvent.EventType = kind == "rotate" ? .rotate : kind == "smartZoom" ? .smartMagnify : kind == "swipe" ? .swipe : .magnify
        guard decoded.type == expected else { return nil }
        return result
    }
    static func dock(action:String,progress:Double,axis:Int,velocity:Double=0) -> CGEvent? {
        guard let e=CGEvent(source:nil) else { return nil }
        let modern=ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
        // UIKit y grows down; the native vertical fluid gesture grows upward.
        let sign=modern && axis == 1 ? 1.0 : -1.0
        let value=progress*sign, speed=velocity*sign
        if modern {
            e.type=CGEventType(rawValue:30)!
            e.timestamp=0
            return TPAttachDockPayload(e,Int32(phase(action)),Int32(axis),value,speed) ? e : nil
        }
        e.setIntegerValueField(CGEventField(rawValue:55)!,value:30)
        e.setIntegerValueField(CGEventField(rawValue:110)!,value:23)
        e.setIntegerValueField(CGEventField(rawValue:132)!,value:phase(action))
        e.setIntegerValueField(CGEventField(rawValue:123)!,value:Int64(axis))
        e.setDoubleValueField(CGEventField(rawValue:124)!,value:value)
        e.setDoubleValueField(CGEventField(rawValue:axis == 2 ? 130 : 129)!,value:speed)
        e.setIntegerValueField(CGEventField(rawValue:135)!,value:Int64(Float(value).bitPattern))
        return e
    }
    static func postDock(_ e: CGEvent) {
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
            e.post(tap:.cgSessionEventTap); return
        }
        guard let companion=CGEvent(source:nil) else { return }
        companion.type=CGEventType(rawValue:29)!
        companion.timestamp=e.timestamp
        e.post(tap:.cgSessionEventTap)
        companion.post(tap:.cgSessionEventTap)
    }
}

final class GestureOutput {
    var settings=MacTrackpadPreferences.read()
    var compatibilityAvailable = NativeGesture.make("magnify",action:"change",value:0.1) != nil
    private var inertia:Timer?
    private var momentumActive=false
    private var velocity=CGPoint.zero
    private var lastTick=0.0
    private var scrollActive=false
    private var transforms=Set<String>()
    private var dockAxis:Int?
    var dockActive:Bool { dockAxis != nil }
    private var dockProgress=0.0
    let continuousDock = ["begin","change","end","cancel"].allSatisfy {
        NativeGesture.dock(action:$0,progress:0.25,axis:1,velocity:0.3) != nil
    }
    private let source=CGEventSource(stateID:.combinedSessionState)
    func interruptMomentum() {
        inertia?.invalidate(); inertia=nil
        if momentumActive { postScroll(x:0,y:0,phase:0,momentum:3); momentumActive=false }
    }
    func cancel() {
        interruptMomentum()
        if scrollActive { postScroll(x:0,y:0,phase:8); scrollActive=false }
        for kind in transforms { NativeGesture.make(kind,action:"cancel")?.post(tap:.cgSessionEventTap) }
        transforms.removeAll()
        if continuousDock, let axis=dockAxis, let event=NativeGesture.dock(action:"cancel",progress:dockProgress,axis:axis) { NativeGesture.postDock(event) }
        dockAxis=nil
    }
    private func postScroll(x:Double,y:Double,phase:Int64,momentum:Int64=0) {
        let sign=settings.naturalScroll ? 1.0 : -1.0
        let x=max(-2000,min(2000,x))*sign,y=max(-2000,min(2000,y))*sign
        guard let e=CGEvent(scrollWheelEvent2Source:source,units:.pixel,wheelCount:2,wheel1:Int32(y.rounded()),wheel2:Int32(x.rounded()),wheel3:0) else { return }
        e.setIntegerValueField(.scrollWheelEventIsContinuous,value:1)
        e.setIntegerValueField(.scrollWheelEventScrollPhase,value:phase)
        e.setIntegerValueField(.scrollWheelEventMomentumPhase,value:momentum)
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1,value:y)
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2,value:x)
        e.post(tap:.cgSessionEventTap)
    }
    func handle(_ event:InputEvent) {
        switch event.kind {
        case "scroll":
            interruptMomentum()
            let phase=NativeGesture.phase(event.action)
            scrollActive=phase == 1 || phase == 2
            postScroll(x:event.x,y:event.y,phase:phase)
        case "inertia":
            guard settings.momentum else { return }
            interruptMomentum(); velocity=CGPoint(x:max(-5000,min(5000,event.x)),y:max(-5000,min(5000,event.y)))
            momentumActive=true; lastTick=ProcessInfo.processInfo.systemUptime
            postScroll(x:0,y:0,phase:0,momentum:1)
            let timer=Timer(timeInterval:1/120,repeats:true) { [weak self] _ in
                guard let self else { return }
                let now=ProcessInfo.processInfo.systemUptime,dt=min(0.05,now-self.lastTick); self.lastTick=now
                self.postScroll(x:self.velocity.x*dt,y:self.velocity.y*dt,phase:0,momentum:2)
                let decay=exp(-6*dt); self.velocity.x *= decay; self.velocity.y *= decay
                if hypot(self.velocity.x,self.velocity.y)<8 { self.interruptMomentum() }
            }
            inertia=timer; RunLoop.main.add(timer,forMode:.common)
        case "magnify","rotate":
            guard compatibilityAvailable else { return }
            if event.action == "begin" { transforms.insert(event.kind) }
            if event.action == "end" || event.action == "cancel" { transforms.remove(event.kind) }
            NativeGesture.make(event.kind,action:event.action,value:max(-90,min(90,event.x)))?.post(tap:.cgSessionEventTap)
        case "dock":
            let axis=event.y == 1 ? 1 : 2
            if event.action != "begin" && dockAxis == nil { return }
            if event.action == "begin", let previous=dockAxis, continuousDock,
               let cancel=NativeGesture.dock(action:"cancel",progress:dockProgress,axis:previous) { NativeGesture.postDock(cancel) }
            dockProgress=event.x; dockAxis=event.action == "end" || event.action == "cancel" ? nil : axis
            if !continuousDock {
                if event.action == "end", abs(event.x)>0.2 {
                    system(axis == 1 ? (event.x>0 ? "spaceLeft" : "spaceRight") : (event.x<0 ? "missionControl" : "appWindows"))
                }
            } else {
                let velocity=event.action == "end" ? max(-20,min(20,event.velocity ?? 0)) : 0
                if let dock=NativeGesture.dock(action:event.action,progress:max(-1.5,min(1.5,event.x)),axis:axis,velocity:velocity) { NativeGesture.postDock(dock) }
            }
        case "page": NativeGesture.make("swipe",action:"end",value:event.x > 0 ? 8 : 4)?.post(tap:.cgSessionEventTap)
        default: break
        }
    }
    func smartZoom() { NativeGesture.make("smartZoom",action:"end")?.post(tap:.cgSessionEventTap) }
    func system(_ action:String) {
        // Respect configured keyboard shortcuts, including explicit disabling.
        let map:[String:(String,CGKeyCode,CGEventFlags)] = ["spaceLeft":("79",123,.maskControl),"spaceRight":("81",124,.maskControl),"missionControl":("32",126,.maskControl),"appWindows":("33",125,.maskControl),"desktop":("36",103,[]),"applications":("160",131,[]),"notifications":("163",0,[]),"lookup":("70",2,[.maskControl,.maskCommand])]
        guard let (id,defaultKey,defaultFlags)=map[action] else { return }
        let domain="com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        let hotkeys=CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,domain) as? [String:[String:Any]]
        let entry=hotkeys?[id]
        if (entry?["enabled"] as? NSNumber)?.boolValue == false { return }
        let parameters=(entry?["value"] as? [String:Any])?["parameters"] as? [NSNumber]
        var key=defaultKey, flags=defaultFlags
        if let p=parameters,p.count==3,p[1].intValue<128 { key=CGKeyCode(p[1].intValue); flags=CGEventFlags(rawValue:p[2].uint64Value) }
        else if action == "notifications" { return } // No default shortcut exists; show limitation in the gesture guide.
        else if action == "applications" {
            if let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple.launchpad.launcher") { NSWorkspace.shared.openApplication(at:url,configuration:.init()) }
            else { NSWorkspace.shared.open(URL(fileURLWithPath:"/Applications",isDirectory:true)) }
            return
        }
        for down in [true,false] { let e=CGEvent(keyboardEventSource:nil,virtualKey:key,keyDown:down); e?.flags=flags; e?.post(tap:.cghidEventTap) }
    }
}
