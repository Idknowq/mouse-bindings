#include "MultitouchBridge.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stddef.h>
#include <stdio.h>

// Private ABI declarations adapted from OpenMultitouchSupport (MIT).
// See THIRD_PARTY.md. No third-party executable is bundled.
typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTVector;
typedef struct {
    int frame;
    double timestamp;
    int identifier, state, fingerID, handID;
    MTVector normalizedPosition;
    float total, pressure, angle, majorAxis, minorAxis;
    MTVector absolutePosition;
    int field14, field15;
    float density;
} MTTouch;
_Static_assert(sizeof(MTTouch) == 96, "Unexpected multitouch contact stride");
_Static_assert(offsetof(MTTouch, normalizedPosition) == 32, "Unexpected position offset");

typedef void *MTDevice;
typedef void (*MTCallback)(MTDevice, MTTouch *, int, double, int);
static CFArrayRef (*createList)(void);
static int (*getFamily)(MTDevice, int *);
static bool (*isBuiltIn)(MTDevice);
static bool (*isRunning)(MTDevice);
static io_service_t (*getService)(MTDevice);
static int (*startDevice)(MTDevice, int);
static int (*stopDevice)(MTDevice);
static void (*registerCallback)(MTDevice, MTCallback);
static void (*unregisterCallback)(MTDevice, MTCallback);
static void *framework;
static CFArrayRef devices;
static MTDevice current;
static MBFrameHandler client;
static void *clientContext;
static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
static char error[512];
static IONotificationPortRef notificationPort;
static io_iterator_t addedIterator, removedIterator;
static MBDeviceHandler deviceHandler;
static void *deviceContext;

static bool loadFramework(void) {
    if (framework) return true;
    void *handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
                          RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        snprintf(error, sizeof(error), "Cannot load MultitouchSupport: %s", dlerror());
        return false;
    }
#define LOAD(variable, name) do { \
    *(void **)(&variable) = dlsym(handle, name); \
    if (!variable) { \
        snprintf(error, sizeof(error), "Missing private API: %s", name); \
        dlclose(handle); return false; \
    } \
} while (0)
    LOAD(createList, "MTDeviceCreateList");
    LOAD(getFamily, "MTDeviceGetFamilyID");
    LOAD(isBuiltIn, "MTDeviceIsBuiltIn");
    LOAD(isRunning, "MTDeviceIsRunning");
    LOAD(getService, "MTDeviceGetService");
    LOAD(startDevice, "MTDeviceStart");
    LOAD(stopDevice, "MTDeviceStop");
    LOAD(registerCallback, "MTRegisterContactFrameCallback");
    LOAD(unregisterCallback, "MTUnregisterContactFrameCallback");
#undef LOAD
    framework = handle;
    return true;
}

static void receiveFrame(MTDevice device, MTTouch *touches, int count, double timestamp, int frame) {
    // The framework is an undocumented boundary; reject an incompatible frame.
    if (count < 0 || count > 32 || (count && !touches)) return;
    MBContact contacts[32];
    for (int i = 0; i < count; i++) {
        contacts[i] = (MBContact){ touches[i].identifier, touches[i].state,
            touches[i].normalizedPosition.position.x, touches[i].normalizedPosition.position.y };
    }
    pthread_mutex_lock(&mutex);
    MBFrameHandler callback = device == current ? client : NULL;
    void *context = clientContext;
    pthread_mutex_unlock(&mutex);
    if (callback) callback(contacts, count, timestamp, context);
}

void MBStop(void) {
    pthread_mutex_lock(&mutex);
    MTDevice old = current;
    current = NULL;
    client = NULL;
    clientContext = NULL;
    pthread_mutex_unlock(&mutex);
    // The driver can wait for a callback: never stop while holding the mutex.
    if (old) {
        unregisterCallback(old, receiveFrame);
        stopDevice(old);
    }
    if (devices) { CFRelease(devices); devices = NULL; }
}

bool MBStart(MBFrameHandler handler, void *context) {
    MBStop();
    error[0] = '\0';
    if (!loadFramework()) return false;
    devices = createList();
    for (CFIndex i = 0; devices && i < CFArrayGetCount(devices); i++) {
        MTDevice device = (MTDevice)CFArrayGetValueAtIndex(devices, i);
        int family = 0;
        // Family 112 is Magic Mouse. An external trackpad is not a mouse.
        if (getFamily(device, &family) != 0 || family != 112 || isBuiltIn(device)) continue;
        pthread_mutex_lock(&mutex);
        current = device;
        client = handler;
        clientContext = context;
        pthread_mutex_unlock(&mutex);
        registerCallback(device, receiveFrame);
        int result = startDevice(device, 0);
        if (result == 0 && isRunning(device)) return true;
        snprintf(error, sizeof(error), "Cannot start Magic Mouse touch input (%d). Check Input Monitoring.", result);
        MBStop();
        return false;
    }
    snprintf(error, sizeof(error), "No connected Magic Mouse found. Connect it over Bluetooth, then retry.");
    MBStop();
    return false;
}

bool MBIsRunning(void) {
    return current && isRunning(current) && IORegistryEntryInPlane(getService(current), kIOServicePlane);
}

const char *MBLastError(void) { return error; }

static void devicesChanged(void *context, io_iterator_t iterator) {
    io_object_t object;
    bool changed = false;
    while ((object = IOIteratorNext(iterator))) { IOObjectRelease(object); changed = true; }
    if (changed && deviceHandler) deviceHandler(deviceContext);
}

void MBWatchDevices(MBDeviceHandler handler, void *context) {
    MBUnwatchDevices();
    notificationPort = IONotificationPortCreate(kIOMainPortDefault);
    if (!notificationPort) return;
    CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(notificationPort), kCFRunLoopCommonModes);
    // Drain initial matches before enabling client notifications.
    IOServiceAddMatchingNotification(notificationPort, kIOFirstMatchNotification,
        IOServiceMatching("AppleMultitouchDevice"), devicesChanged, NULL, &addedIterator);
    devicesChanged(NULL, addedIterator);
    IOServiceAddMatchingNotification(notificationPort, kIOTerminatedNotification,
        IOServiceMatching("AppleMultitouchDevice"), devicesChanged, NULL, &removedIterator);
    devicesChanged(NULL, removedIterator);
    deviceHandler = handler;
    deviceContext = context;
}

void MBUnwatchDevices(void) {
    deviceHandler = NULL; deviceContext = NULL;
    if (addedIterator) { IOObjectRelease(addedIterator); addedIterator = 0; }
    if (removedIterator) { IOObjectRelease(removedIterator); removedIterator = 0; }
    if (notificationPort) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(notificationPort), kCFRunLoopCommonModes);
        IONotificationPortDestroy(notificationPort); notificationPort = NULL;
    }
}
