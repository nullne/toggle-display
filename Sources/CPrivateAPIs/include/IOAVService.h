#ifndef IOAVService_h
#define IOAVService_h

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>

// Use a struct-based opaque type to avoid Swift's CFTypeRef Ref-stripping
typedef struct OpaqueIOAVService *IOAVServiceRef;

extern IOAVServiceRef IOAVServiceCreateWithService(
    CFAllocatorRef allocator, io_service_t service);

extern IOReturn IOAVServiceReadI2C(
    IOAVServiceRef service,
    uint32_t chipAddress,
    uint32_t dataAddress,
    void *outputBuffer,
    uint32_t outputBufferSize);

extern IOReturn IOAVServiceWriteI2C(
    IOAVServiceRef service,
    uint32_t chipAddress,
    uint32_t dataAddress,
    void *inputBuffer,
    uint32_t inputBufferSize);

extern CFDataRef IOAVServiceCopyEDID(IOAVServiceRef service);

#endif
