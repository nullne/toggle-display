#ifndef IOPMLib_h
#define IOPMLib_h

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>

typedef uint32_t IOPMAssertionID;
typedef uint32_t IOPMAssertionLevel;

#define kIOPMAssertionLevelOn  255
#define kIOPMAssertionLevelOff 0

extern const CFStringRef kIOPMAssertionTypePreventUserIdleDisplaySleep;

extern IOReturn IOPMAssertionCreateWithName(
    CFStringRef assertionType,
    IOPMAssertionLevel assertionLevel,
    CFStringRef reasonForActivity,
    IOPMAssertionID *assertionID);

extern IOReturn IOPMAssertionRelease(IOPMAssertionID assertionID);

#endif
