#ifndef TOUCHPAD_NATIVE_INPUT_H
#define TOUCHPAD_NATIVE_INPUT_H
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
void *TPAccelerationCreate(CFArrayRef curves, double index, double resolution);
void TPAccelerationRelease(void *curve);
double TPAccelerationEvaluate(void *curve, double velocity);
bool TPAttachDockPayload(CGEventRef event, int phase, int axis, double progress, double velocity);
bool TPCheckDockPayload(CGEventRef event, int phase, int axis, double progress, double velocity);
#ifdef __cplusplus
}
#endif
#endif
