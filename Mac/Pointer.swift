import AppKit
import IOKit

// Phone points are calibrated to 160 points/inch, then evaluated by the actual
// Apple HID curve installed on this Mac. The phone's sensitivity is a size trim.
final class PointerAcceleration {
    private var curve: UnsafeMutableRawPointer?
    private var resolution = 400.0
    private var index = Double.nan
    private var curves: NSArray?
    private(set) var available = false
    init() { refresh(index: MacTrackpadPreferences.read().trackingSpeed) }
    deinit { TPAccelerationRelease(curve) }
    func refresh(index: Double) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDEventService"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var found: NSArray?
        var dpi = 400.0
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let type=IORegistryEntryCreateCFProperty(service,"HIDPointerAccelerationType" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? String
            guard type == "HIDTrackpadAcceleration" else { continue }
            found=IORegistryEntryCreateCFProperty(service,"HIDAccelCurves" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? NSArray
            if let number=IORegistryEntryCreateCFProperty(service,"HIDPointerResolution" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? NSNumber {
                dpi=number.doubleValue/65536
            }
            if found != nil { break }
        }
        guard index != self.index || found != curves || dpi != resolution else { return }
        TPAccelerationRelease(curve); curve=nil
        self.index=index; curves=found; resolution=dpi
        if let found, dpi > 0 { curve=TPAccelerationCreate(found as CFArray,index,dpi) }
        available=curve != nil
    }
    func apply(x: Double, y: Double, dt: Double) -> CGPoint {
        guard let curve else { return CGPoint(x:x,y:y) }
        let dx=x*resolution/160, dy=y*resolution/160
        // Evaluate velocity at Apple's 67 Hz reference interval. Keep fractional
        // phone samples; packet scheduling / 60 vs 120 Hz must not change gain.
        let speed=max(1/65536, hypot(dx,dy)/(67*max(0.001,min(0.25,dt))))
        let gain=TPAccelerationEvaluate(curve,speed)/speed
        guard gain.isFinite, gain >= 0 else { return CGPoint(x:x,y:y) }
        return CGPoint(x:dx*gain,y:dy*gain)
    }
}

enum DesktopBounds {
    static func screens() -> [CGRect] {
        var ids=[CGDirectDisplayID](repeating:0,count:32), count:UInt32=0
        guard CGGetActiveDisplayList(32,&ids,&count) == .success else { return [CGDisplayBounds(CGMainDisplayID())] }
        return ids.prefix(Int(count)).map(CGDisplayBounds).filter { !$0.isEmpty }
    }
    // Use the real display arrangement, including displays left/above the main one.
    // Clipping against the union keeps edge travel from accumulating off-screen.
    static func constrain(_ point: CGPoint, from origin: CGPoint? = nil, to screens: [CGRect]) -> CGPoint {
        if screens.contains(where: { $0.contains(point) }) { return point }
        // When pushing against an outside edge, slide along the current screen;
        // do not snap diagonally into a nearby display that is above or below it.
        let current=origin.flatMap { p in screens.first { $0.contains(p) } }
        return (current.map { [$0] } ?? screens).map { r in
            CGPoint(x:min(r.maxX-0.001,max(r.minX,point.x)),y:min(r.maxY-0.001,max(r.minY,point.y)))
        }.min { hypot($0.x-point.x,$0.y-point.y)<hypot($1.x-point.x,$1.y-point.y) } ?? point
    }
}
