#ifndef MOUSE_BINDINGS_MULTITOUCH_H
#define MOUSE_BINDINGS_MULTITOUCH_H
#include <stdbool.h>
#include <stdint.h>

typedef struct {
    int32_t identifier, state;
    float x, y;
} MBContact;

// Contacts are valid only for the duration of this callback. Copy before returning.
typedef void (*MBFrameHandler)(const MBContact *, int32_t count, double timestamp, void *context);
// Lifecycle calls must be serialized. This bridge owns one Magic Mouse session.
bool MBStart(MBFrameHandler handler, void *context);
void MBStop(void);
bool MBIsRunning(void);
const char *MBLastError(void);
typedef void (*MBDeviceHandler)(void *context);
// Device notifications are delivered on the main run loop.
void MBWatchDevices(MBDeviceHandler handler, void *context);
void MBUnwatchDevices(void);
#endif
