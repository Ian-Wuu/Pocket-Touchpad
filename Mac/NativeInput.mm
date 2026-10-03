#import "NativeInput.h"
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <cmath>

// Read-only bridge to Apple's installed implementation. No copied acceleration curve.
// ABI declaration from Apple IOHIDFamily/IOHIDAccelerationAlgorithm.hpp.
class IOHIDAccelerationAlgorithm {
public:
    enum Type { Table, Parametric, Unknown };
    virtual ~IOHIDAccelerationAlgorithm() {}
    virtual double multiplier(double value) { return value; }
    virtual Type getType() const { return Unknown; }
    virtual void serialize(CFMutableDictionaryRef) const = 0;
};
void *TPAccelerationCreate(CFArrayRef curves, double index, double resolution) {
    static void *library = dlopen("/System/Library/HIDPlugins/IOHIDPointerScrollFilter.plugin/Contents/MacOS/IOHIDPointerScrollFilter", RTLD_NOW | RTLD_LOCAL);
    using Create = IOHIDAccelerationAlgorithm *(*)(CFArrayRef, double, double, double);
    static Create create = library ? (Create)dlsym(library, "_ZN27IOHIDParametricAcceleration20CreateWithParametersEPK9__CFArrayddd") : nullptr;
    // Future OS versions must be revalidated before using a private C++ ABI.
    NSInteger os = NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
    if (!create || os < 26 || os > 27 || !curves || index < 0 || resolution <= 0) return nullptr;
    return create(curves, index, resolution, 67.0);
}
void TPAccelerationRelease(void *curve) { delete static_cast<IOHIDAccelerationAlgorithm *>(curve); }
double TPAccelerationEvaluate(void *curve, double velocity) {
    if (!curve || !std::isfinite(velocity) || velocity <= 0) return velocity;
    return static_cast<IOHIDAccelerationAlgorithm *>(curve)->multiplier(velocity);
}

// Runtime selectors / field layout documented by the MIT MMF27 companion repair.
// Use the system setter, never write through offsets in an opaque CGEvent object.
@interface TPHIDEvent : NSObject
- (instancetype)initWithType:(uint32_t)type timestamp:(uint64_t)timestamp senderID:(uint64_t)sender;
- (void)setIntegerValue:(NSInteger)value forField:(uint32_t)field;
- (NSInteger)integerValueForField:(uint32_t)field;
- (void)setDoubleValue:(double)value forField:(uint32_t)field;
- (double)doubleValueForField:(uint32_t)field;
- (void)appendEvent:(TPHIDEvent *)event;
@property uint32_t options;
@property(readonly) uint32_t type;
@property(readonly) NSArray<TPHIDEvent *> *children;
@end
struct DockAPI {
    using Set = void (*)(CGEventRef, CFTypeRef);
    using Copy = CFTypeRef (*)(CGEventRef);
    Set set = nullptr;
    Copy copy = nullptr;
    Class eventClass = Nil;
    DockAPI() {
        void *library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW | RTLD_LOCAL);
        if (!library) return;
        set = (Set)dlsym(library,"SLEventSetIOHIDEvent");
        copy = (Copy)dlsym(library,"SLEventCopyIOHIDEvent");
        eventClass = NSClassFromString(@"HIDEvent");
    }
};
static DockAPI &dockAPI() { static DockAPI api; return api; }
bool TPCheckDockPayload(CGEventRef event, int phase, int axis, double progress, double velocity) {
    auto &api = dockAPI();
    if (!api.copy) return false;
    TPHIDEvent *hid = CFBridgingRelease(api.copy(event));
    if (!hid || hid.type != 23 || (hid.options >> 24) != phase ||
        [hid integerValueForField:(23 << 16) | 1] != axis ||
        [hid integerValueForField:(23 << 16) | 5] != 3 ||
        std::abs([hid doubleValueForField:(23 << 16) | 2]-progress) > 0.0001) return false;
    if (phase == 4 || phase == 8) {
        TPHIDEvent *v = hid.children.firstObject;
        if (!v || v.type != 9 || std::abs([v doubleValueForField:(9 << 16) | (axis == 2 ? 1 : 0)]-velocity) > 0.0001) return false;
    }
    return true;
}
bool TPAttachDockPayload(CGEventRef event, int phase, int axis, double progress, double velocity) {
    auto &api = dockAPI();
    if (!event || !api.set || !api.copy || !api.eventClass || !std::isfinite(progress) || !std::isfinite(velocity)) return false;
    TPHIDEvent *hid = [[api.eventClass alloc] initWithType:23 timestamp:CGEventGetTimestamp(event) senderID:0];
    if (!hid) return false;
    hid.options = (uint32_t)phase << 24;
    [hid setIntegerValue:axis forField:(23 << 16) | 1];
    [hid setIntegerValue:3 forField:(23 << 16) | 5];
    [hid setDoubleValue:progress forField:(23 << 16) | 2];
    if (phase == 4 || phase == 8) {
        TPHIDEvent *v = [[api.eventClass alloc] initWithType:9 timestamp:CGEventGetTimestamp(event) senderID:0];
        if (!v) return false;
        [v setDoubleValue:velocity forField:(9 << 16) | (axis == 2 ? 1 : 0)];
        [hid appendEvent:v];
    }
    api.set(event, (__bridge CFTypeRef)hid);
    return TPCheckDockPayload(event, phase, axis, progress, velocity);
}
