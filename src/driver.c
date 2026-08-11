#include "MultitouchSupport.h"
#include <Carbon/Carbon.h>
#include <CoreGraphics/CGGeometry.h>
#include <CoreGraphics/CGRemoteOperation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <pthread.h>
// #include "settings.h"

#define try(...)                                                               \
  if ((__VA_ARGS__) == -1) {                                                   \
    fprintf(stderr, "`%s` failed", #__VA_ARGS__);                              \
    exit(1);                                                                   \
  }

// Disable custom cursor movement whenever more than one finger is on the pad
// allows gestures (?) and such
static const bool DISABLE_CURSOR_ON_MULTITOUCH = true;
static const bool RELATIVE_FETCH_POS_EACH_FRAME = true;

typedef struct {
  float x, y, width, height;
} Rectangle;

typedef enum { RELATIVE = 0, ABSOLUTE = 1 } TrackingMode;

typedef struct {
  Rectangle activeArea;
  Rectangle screenMapping;
  CGDirectDisplayID displayId;
  TrackingMode mode;
  float trackingSensitivity; // units: px/(10% of trackpad)
  bool emitMouseEvent;
  double smoothingFactor; // aka JITTER_ALPHA
  double jitterThreshold;
} TrackpadSettings;

TrackpadSettings settings = {
    .activeArea = {0, 0, 1, 1},
    .screenMapping = {0, 0, 1, 1},
    .displayId = 0,
    .mode = ABSOLUTE,
    .trackingSensitivity = 1.0,
    .emitMouseEvent = false,
    .smoothingFactor = 0.9,
    .jitterThreshold = 1.0,
};
CGRect screenBounds;
CGRect* screens;
uint32_t displayCount;
CGSize trackpadDigitizerSize;

int mouseEventNumber = 0;
pthread_mutex_t mouseEventNumber_mutex;
#define MAGIC_NUMBER 727

double rectRatio(double n, double origin, double size) {
  if (n < origin) {
    return 0;
  }
  if (n > origin + size) {
    return 1;
  }
  return (n - origin) / size;
}

double reverseRectRatio(double n, double origin, double size) {
  if (n < 0) {
    return origin;
  }
  return n * size + origin;
}

MTPoint mapToScreen(double normx, double normy) {
  Rectangle *active = &settings.activeArea;
  Rectangle *screen = &settings.screenMapping;

  MTPoint point = {
      .x = rectRatio(normx, active->x, active->width),
      .y = rectRatio(normy, active->y, active->height),
  };

  point.x = reverseRectRatio(point.x, screen->x, screen->width);
  point.y = reverseRectRatio(point.y, screen->y, screen->height);

  point.x *= screenBounds.size.width;
  point.y *= screenBounds.size.height;
  return point;
}

CGRect* getScreenFromPoint(int x, int y) {
  for (int i = 0; i < displayCount; i++) {
    if (x >= screens[i].origin.x && x < screens[i].origin.x + screens[i].size.width &&
        y >= screens[i].origin.y && y < screens[i].origin.y + screens[i].size.height) {
      return &screens[i];
    }
  }
  return NULL;// id rather not return NULL to be honest.
}

// emitMouseEvent causes conflict with the native driver and so with relative and
// even absolute it causes jitter and stuff
void moveCursorToAbs(CGPoint point) { // now we're talking screen
  if (settings.emitMouseEvent) {
    CGEventRef event = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, point,
                                               kCGMouseButtonLeft);
    if (event == NULL) {
      CGWarpMouseCursorPosition(point);
      return;
    }
    CGEventSetIntegerValueField(event, kCGEventSourceUserData, MAGIC_NUMBER);
    CGEventSetIntegerValueField(event, kCGMouseEventSubtype, 3);

    // try(pthread_mutex_lock(&mouseEventNumber_mutex));
    // CGEventSetIntegerValueField(event, kCGMouseEventNumber, mouseEventNumber);
    // try(pthread_mutex_unlock(&mouseEventNumber_mutex));

    CGEventPost(kCGHIDEventTap, event);
    CFRelease(event);
  } else {
    CGWarpMouseCursorPosition(point);
  }
}

bool relativeWereFingersReleased = false;

void handleRelativeMoveCursor(double normx, double normy) {
  static double lastNormX = -1.0;
  static double lastNormY = -1.0;
  static CGPoint lastCursorPos = {0, 0};

  if (relativeWereFingersReleased) {
    lastNormX = normx;
    lastNormY = normy;
    lastCursorPos = CGEventGetLocation(CGEventCreate(NULL));
    relativeWereFingersReleased = false;
    return;
  }

  if (lastNormX < 0.0 || lastNormY < 0.0)
    return;

  double dx = normx - lastNormX;
  double dy = normy - lastNormY;

  // currently it's technically mapped to full area
  // dx *= screenBounds.size.width * settings.trackingSensitivity;
  // dy *= screenBounds.size.height * settings.trackingSensitivity;
  double trackpadAsr = trackpadDigitizerSize.width / trackpadDigitizerSize.height;
  // so currently (dx, dy) is normalized (1,1)
  // we need to convert it to (1, tds.height / tds.width) so that the axes are same sens
  dy /= trackpadAsr;
  // now multiply by sens
  dx *= settings.trackingSensitivity * 1000;
  dy *= settings.trackingSensitivity * 1000;

  double x = lastCursorPos.x + dx;
  double y = lastCursorPos.y + dy;

  double threshold = settings.jitterThreshold;
  double alpha = settings.smoothingFactor;

  double dist2 = dx * dx + dy * dy;
  if (dist2 < threshold * threshold) {
    x = lastCursorPos.x;
    y = lastCursorPos.y;
  } else {
    x = lastCursorPos.x + alpha * dx;
    y = lastCursorPos.y + alpha * dy;
  }

  moveCursorToAbs((CGPoint){x, y});

  lastNormX = normx;
  lastNormY = normy;
  // lastCursorPos = (CGPoint){x, y};
  lastCursorPos = CGEventGetLocation(CGEventCreate(NULL));
}

void handleAbsoluteMoveCursor(double normx, double normy) {
  MTPoint screenPoint = mapToScreen(normx, normy);
  static double lastX = -1.0;
  static double lastY = -1.0;
  double x = screenPoint.x;
  double y = screenPoint.y;

  // Simple stabiliser: ignore very small moves and smooth bigger ones

  // Minimum movement (in screen pixels) before we move the cursor (change in
  // settings.def.h / settings.h)
  double threshold = settings.jitterThreshold;
  double alpha = settings.smoothingFactor; // from settings

  if (lastX >= 0.0 && lastY >= 0.0) {
    double dx = x - lastX;
    double dy = y - lastY;
    double dist2 = dx * dx + dy * dy;

    if (dist2 < threshold * threshold) { // we're still gonna warp, just at the
                                         // previous position
      x = lastX;
      y = lastY;
    } else {
      // Low-pass filter: move part-way toward the new point
      x = lastX + alpha * dx;
      y = lastY + alpha * dy;
    }
  }

  lastX = x;
  lastY = y;

  CGPoint point = (CGPoint){
      .x = x < 0                   ? 0
           : x >= screenBounds.size.width ? screenBounds.size.width - 1
                                   : x,
      .y = y < 0                    ? 0
           : y >= screenBounds.size.height ? screenBounds.size.height - 1
                                    : y,
  };
  point.x += screenBounds.origin.x;
  point.y += screenBounds.origin.y;

  moveCursorToAbs(point);
}

void moveCursor(double normx, double normy) {
  if (settings.mode == RELATIVE) {
    handleRelativeMoveCursor(normx, normy);
  } else {
    handleAbsoluteMoveCursor(normx, normy);
  }
}

// moving cursor here increases sensitivity to finger
// detecting gesture:
// Beginning of a gesture may start with one finger or more than one fingers.
// Simply checking how many fingers touched is not enough.
// Discard coordinates of the first callback call for each cursor movement
// and wait for the second call to make sure it is not a gesture.
int trackpadCallback(MTDeviceRef device, MTTouch *data, size_t nFingers, double timestamp, size_t frame) {
  #define GESTURE_PHASE_NONE 0
  #define GESTURE_PHASE_MAYSTART 1
  #define GESTURE_PHASE_BEGAN 2
  #define GESTURE_TIMEOUT 0.02
  // timestamp arg is in seconds
  // if touchpad is not touched, this callback is not called. the negated version of this is true aswell

  static MTPoint fingerPosition = {0, 0},
                 oldFingerPosition = {0, 0}; // normalized finger positioning
  static int32_t oldPathIndex = -1;
  static double oldTimeStamp = 0, startTrackTimeStamp = 0;
  static size_t oldFingerCount = 1;
  static int gesturePhase = GESTURE_PHASE_NONE;
  // FIXME: how many fingers can magic trackpad detect?
  static bool gesturePaths[20] = {0};

  if (oldFingerCount != nFingers)
    relativeWereFingersReleased = true;
  
  if (nFingers == 0) {
    // all fingers lifted, clearing gesture fingers
    for (int i = 0; i < 20; i++) {
      gesturePaths[i] = false;
    }
    gesturePhase = GESTURE_PHASE_NONE;
    oldFingerCount = nFingers;
    startTrackTimeStamp = 0;
    // lastX = -1.0;
    // lastY = -1.0;
    relativeWereFingersReleased = true;
    return 0;
  }

  if (!startTrackTimeStamp) {
    startTrackTimeStamp = timestamp;
  }

  // we are back to one finger
  // we must wait another call to ensure this is not a gesture.
  if (oldFingerCount != 1 && nFingers == 1 && !gesturePhase) {
    gesturePhase = GESTURE_PHASE_MAYSTART;
    oldFingerCount = nFingers;
    // lastX = (double) (&data[0])->normalizedVector.position.x;
    // lastY = (double) (&data[0])->normalizedVector.position.y;
    relativeWereFingersReleased = true;
    return 0;
  };

  // we have not waited the time out yet to ensure this is not a gesture
  if (nFingers == 1 && timestamp - startTrackTimeStamp < GESTURE_TIMEOUT) {
    relativeWereFingersReleased = true;
    return 0;
  }

  // if we are beginning a gesture
  if (nFingers != 1 && (timestamp - startTrackTimeStamp < GESTURE_TIMEOUT ||
                        gesturePhase != GESTURE_PHASE_NONE)) {
    gesturePhase = GESTURE_PHASE_BEGAN;
    for (int i = 0; i < nFingers; i++) {
      gesturePaths[data[i].pathIndex] = true;
    }
    if (!DISABLE_CURSOR_ON_MULTITOUCH || nFingers <= 1) {
      moveCursor(fingerPosition.x, fingerPosition.y);
    }
    oldFingerCount = nFingers;
    return 0;
  };

  // keeping one finger on trackpad when lifting up fingers
  // at the end of gesture
  if (gesturePhase == GESTURE_PHASE_BEGAN) {
    for (int i = 0; i < nFingers; i++) {
      if (gesturePaths[data[i].pathIndex]) {
        if (!(DISABLE_CURSOR_ON_MULTITOUCH && nFingers > 1)) {
          moveCursor(fingerPosition.x, fingerPosition.y);
        }
        return 0;
      }
    }
  }

  gesturePhase = GESTURE_PHASE_NONE;

  // remembers currently using which finger
  MTTouch *f = &data[0];
  for (int i = 0; i < nFingers; i++) {
    if (data[i].pathIndex == oldPathIndex) {
      f = &data[i];
      break;
    }
  }

  oldFingerPosition = fingerPosition;
  // use settings.h if no command line arguments are given
  fingerPosition = (MTPoint){f->normalizedVector.position.x,
                             1 - f->normalizedVector.position.y};
  MTPoint velocity = f->normalizedVector.velocity;

  if (fingerPosition.x < 0 || fingerPosition.y < 0) {
    // Only lock cursor when finger starts path on dead zone
    if (f->pathIndex == oldPathIndex) {
      if (fingerPosition.x < 0) {
        fingerPosition.x = oldFingerPosition.x +
                           velocity.x * (timestamp - oldTimeStamp) * 1000;
      }
      if (fingerPosition.y < 0) {
        fingerPosition.y = oldFingerPosition.y -
                           velocity.y * (timestamp - oldTimeStamp) * 1000;
      }

    } else {
      fingerPosition = oldFingerPosition;
    }
  } else {
    oldPathIndex = f->pathIndex;
  }

  if (!DISABLE_CURSOR_ON_MULTITOUCH || nFingers <= 1) {
    moveCursor(fingerPosition.x, fingerPosition.y);
  }

  oldTimeStamp = timestamp;
  return 0;
}

bool check_privileges(void) {
  bool result;
  const void *keys[] = {kAXTrustedCheckOptionPrompt};
  const void *values[] = {kCFBooleanTrue};

  CFDictionaryRef options;
  options = CFDictionaryCreate(
      kCFAllocatorDefault, keys, values, sizeof(keys) / sizeof(*keys),
      &kCFCopyStringDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

  result = AXIsProcessTrustedWithOptions(options);
  CFRelease(options);

  return result;
}

Rectangle parseRectangle(char *s) {
  char *token[4 + 1];
  int i = 0;
  for (; (token[i] = strsep(&s, ",")) != NULL && i < 4; i++) {
  }
  if (i != 4 || token[4] != NULL) {
    fputs("Rectangle format: x,y,width,height and numbers in range [0, 1]",
          stderr);
    exit(1);
  }
  float num[4];
  for (i = 0; i < 4; i++) {
    char *endptr;
    num[i] = strtof(token[i], &endptr);
    if (*endptr) {
      fprintf(stderr, "Invalid number %s\n", token[i]);
      exit(1);
    }
  }
  return (Rectangle){num[0], num[1], num[2], num[3]};
}

void parseSettings(int argc, char **argv) {
  int opt;
  while ((opt = getopt(argc, argv, "i:o:d:s:t:j:em:")) != -1) {
    switch (opt) {
    case 'i':
      settings.activeArea = parseRectangle(optarg);
      break;
    case 'o':
      settings.screenMapping = parseRectangle(optarg);
      break;
    case 'e':
      settings.emitMouseEvent = true;
      break;
    case 'm':
      if (strcmp(optarg, "Absolute") == 0 || strcmp(optarg, "absolute") == 0) {
        settings.mode = ABSOLUTE;
      } else {
        settings.mode = RELATIVE;
      }

      break;
    case 'd':
      settings.displayId = atoi(optarg);
      break;
    case 's':
      settings.smoothingFactor = atof(optarg);
      break;
    case 'j':
      settings.jitterThreshold = atof(optarg);
      break;
    case 't':
      settings.trackingSensitivity = atof(optarg);
      break;
    default:
      // fprintf(stderr,
      //         "Usage: %s [-i x,y,w,h] [-o x,y,w,h] [-e] [-m
      //         Absolute|Relative]\n", argv[0]);
      // exit(EXIT_FAILURE);
      printf("[driver] got invalid option %s, this is bad.\n", optarg);
    }
  }
}

CGEventRef loggerCallback(CGEventTapProxy proxy, CGEventType type,
                          CGEventRef event, void *context) {
  int magic_number = CGEventGetIntegerValueField(event, kCGEventSourceUserData);
  if (magic_number == MAGIC_NUMBER) {
    return event;
  }
  int eventNumber = CGEventGetIntegerValueField(event, kCGMouseEventNumber);
  try(pthread_mutex_lock(&mouseEventNumber_mutex));
  mouseEventNumber = eventNumber;
  try(pthread_mutex_unlock(&mouseEventNumber_mutex));
  return event;
}

int main(int argc, char **argv) {
  // if (!check_privileges()) {
  //     printf("Requires accessbility privileges\n");
  //     return 1;
  // }
  printf("[driver] started!\n");
  parseSettings(argc, argv);
  printf("[driver] settings: %f, %f, %f, %f\n", settings.activeArea.x,
         settings.activeArea.y, settings.activeArea.width,
         settings.activeArea.height);
  printf("[driver] screen mapping: %f, %f, %f, %f\n", settings.screenMapping.x,
         settings.screenMapping.y, settings.screenMapping.width,
         settings.screenMapping.height);
  printf("[driver] mode: %s\n",
         settings.mode == ABSOLUTE ? "Absolute" : "Relative");
  printf("[driver] emit mouse event: %s\n",
         settings.emitMouseEvent ? "true" : "false");
  printf("[driver] tracking sensitivity: %f\n", settings.trackingSensitivity);
  printf("[driver] display ID: %u\n", (unsigned int)settings.displayId);

  screenBounds = CGDisplayBounds(settings.displayId);
  screenBounds.size = screenBounds.size;

  CGDirectDisplayID* displayIDs;
  CGGetActiveDisplayList(0, NULL, &displayCount);
  displayIDs = malloc(displayCount * sizeof(CGDirectDisplayID));
  CGGetActiveDisplayList(displayCount, displayIDs, &displayCount);
  screens = malloc(displayCount * sizeof(CGRect));
  for (int i = 0; i < displayCount; i++) {
    screens[i] = CGDisplayBounds(displayIDs[i]);
  }
  free(displayIDs);
  printf("[driver] found %d displays\n", displayCount);

  try(pthread_mutex_init(&mouseEventNumber_mutex, NULL));

  // start trackpad service
  // https://github.com/JitouchApp/Jitouch-project/blob/3b5018e4bc839426a6ce0917cea6df753d19da10/Application/Gesture.m#L2926-L2954
  CFArrayRef deviceList = MTDeviceCreateList();
  for (CFIndex i = 0; i < CFArrayGetCount(deviceList); i++) {
    MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(deviceList, i);
    int familyId;
    MTDeviceGetFamilyID(device, &familyId);
    if (familyId >= 98 && familyId != 112 &&
        familyId != 113 // Magic Mouse 1&2 / 3
    ) {
      MTRegisterContactFrameCallback(device,
                                     (MTFrameCallbackFunction)trackpadCallback);
      MTDeviceStart(device, 0);
      // we are kind of going to assume that ther eis only on device we are
      // using.
      // TODO: mutli device
      printf("[driver] registered device %d\n", familyId);
      int surfaceWidth, surfaceHeight;
      MTDeviceGetSensorSurfaceDimensions(device, &surfaceWidth, &surfaceHeight);
      // returned from MTDeviceGetSensorSurfaceDimensions is the W H in
      // centimillimeters it seems on my macbook air 13in m3 is returns 12194,
      // 7408, and it physically measures ~127mm x ~80mm so im assuming it
      // returns centimillimeter active area, and that the active area is not
      // 100% of the trackpad either way it should be close enough
      printf("[driver] surface dimensions: %d, %d\n", surfaceWidth,
             surfaceHeight);
      trackpadDigitizerSize = (CGSize){surfaceWidth, surfaceHeight};
      break;
    }
  }

  // simply an infinite loop waiting for app to quit
  CFRunLoopRun();
  return 0;
}
