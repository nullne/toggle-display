import Foundation
import IOKit
import CoreGraphics
import CPrivateAPIs

final class DDCService {
    private let ddcChipAddress: UInt32 = 0x37
    private let ddcDataAddress: UInt32 = 0x51

    private let vcpPowerMode: UInt8 = 0xD6
    private let powerOn: UInt8 = 0x01
    private let powerOff: UInt8 = 0x05
    private let setVCPOpcode: UInt8 = 0x03

    private let maxRetries = 3
    private let retryDelay: UInt32 = 50_000 // 50ms in microseconds

    // Cache discovered services to avoid repeated IORegistry walks
    private var serviceCache: [CGDirectDisplayID: IOAVServiceRef] = [:]

    // MARK: - Public Interface

    func isAvailable(for displayID: CGDirectDisplayID) -> Bool {
        if CGDisplayIsBuiltin(displayID) != 0 { return false }
        return findAVService(for: displayID) != nil
    }

    func setPowerState(displayID: CGDirectDisplayID, on: Bool) {
        guard let service = findAVService(for: displayID) else { return }
        let value: UInt8 = on ? powerOn : powerOff
        setVCPFeature(service: service, code: vcpPowerMode, value: UInt16(value))
    }

    func invalidateCache() {
        serviceCache.removeAll()
    }

    // MARK: - DDC Packet Construction

    private func setVCPFeature(service: IOAVServiceRef, code: UInt8, value: UInt16) {
        var data: [UInt8] = [
            0x84,
            setVCPOpcode,
            code,
            UInt8(value >> 8),
            UInt8(value & 0xFF),
            0
        ]

        var checksum: UInt8 = 0x6E ^ UInt8(ddcDataAddress & 0xFF)
        for i in 0..<5 {
            checksum ^= data[i]
        }
        data[5] = checksum

        for attempt in 1...maxRetries {
            let result = IOAVServiceWriteI2C(
                service,
                ddcChipAddress,
                ddcDataAddress,
                &data,
                UInt32(data.count))

            if result == kIOReturnSuccess {
                return
            }

            if attempt < maxRetries {
                usleep(retryDelay)
            }
        }
    }

    // MARK: - Service Discovery

    private func findAVService(for displayID: CGDirectDisplayID) -> IOAVServiceRef? {
        // Return cached service if available
        if let cached = serviceCache[displayID] {
            return cached
        }

        // Strategy: Read EDID from the IORegistry (safe), not from IOAVServiceCopyEDID (can crash).
        // 1. Find all IODisplayConnect entries and read their EDID + extract vendor/model
        // 2. Map each IODisplayConnect to its parent GPU framebuffer
        // 3. Find the DCPAVServiceProxy that shares the same GPU parent
        // 4. Match the target CGDirectDisplayID via vendor/model

        let targetVendor = CGDisplayVendorNumber(displayID)
        let targetModel = CGDisplayModelNumber(displayID)

        // Find the DCPAVServiceProxy that corresponds to this display
        // by matching via the IODisplayConnect EDID in the IORegistry tree.
        if let service = findAVServiceViaRegistry(vendor: targetVendor, model: targetModel) {
            serviceCache[displayID] = service
            return service
        }

        // Simple fallback: if there's exactly one external display and one DCPAVServiceProxy
        // with a valid IOAVService, use it directly.
        if let service = findSingleExternalAVService() {
            serviceCache[displayID] = service
            return service
        }

        return nil
    }

    /// Find an IOAVService by walking the IORegistry and matching EDID data safely.
    private func findAVServiceViaRegistry(vendor: UInt32, model: UInt32) -> IOAVServiceRef? {
        // Look for IODisplayConnect entries that have our target vendor/model EDID
        guard let displayMatching = IOServiceMatching("IODisplayConnect") else { return nil }

        var displayIterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, displayMatching, &displayIterator) == kIOReturnSuccess else {
            return nil
        }
        defer { IOObjectRelease(displayIterator) }

        var displayEntry = IOIteratorNext(displayIterator)
        while displayEntry != 0 {
            defer {
                IOObjectRelease(displayEntry)
                displayEntry = IOIteratorNext(displayIterator)
            }

            // Read EDID from the IORegistry (this is safe, no crash risk)
            guard let edidProp = IORegistryEntryCreateCFProperty(
                displayEntry, "IODisplayEDID" as CFString, kCFAllocatorDefault, 0
            ) else { continue }

            let edidData = edidProp.takeRetainedValue() as! CFData as Data
            guard edidData.count >= 12 else { continue }

            let edidVendor = (UInt16(edidData[8]) << 8) | UInt16(edidData[9])
            let edidProduct = UInt16(edidData[10]) | (UInt16(edidData[11]) << 8)

            guard UInt32(edidVendor) == vendor && UInt32(edidProduct) == model else { continue }

            // Found the IODisplayConnect with matching EDID.
            // Now walk up to find the associated DCPAVServiceProxy.
            // IODisplayConnect -> IOFramebuffer -> ... -> DCPAV...
            if let avService = findAVServiceInParentChain(of: displayEntry) {
                return avService
            }
        }

        return nil
    }

    /// Walk up the IORegistry parent chain from an IODisplayConnect
    /// to find a sibling or nearby DCPAVServiceProxy, then create an IOAVService.
    private func findAVServiceInParentChain(of entry: io_registry_entry_t) -> IOAVServiceRef? {
        // Walk up to the GPU/controller level
        var current = entry
        IOObjectRetain(current)

        for _ in 0..<8 {  // Don't walk too far
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == kIOReturnSuccess else {
                IOObjectRelease(current)
                return nil
            }
            IOObjectRelease(current)
            current = parent

            // At each level, check if there's a DCPAVServiceProxy child
            if let avService = findAVServiceChild(of: current) {
                IOObjectRelease(current)
                return avService
            }
        }

        IOObjectRelease(current)
        return nil
    }

    /// Look for a DCPAVServiceProxy among the children (recursively, 2 levels) of an entry.
    private func findAVServiceChild(of entry: io_registry_entry_t) -> IOAVServiceRef? {
        var childIterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &childIterator) == kIOReturnSuccess else {
            return nil
        }
        defer { IOObjectRelease(childIterator) }

        var child = IOIteratorNext(childIterator)
        while child != 0 {
            defer {
                IOObjectRelease(child)
                child = IOIteratorNext(childIterator)
            }

            var className = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(child, &className)
            let name = String(cString: className)

            if name == "DCPAVServiceProxy" {
                if let avService = IOAVServiceCreateWithService(kCFAllocatorDefault, child) {
                    return avService
                }
            }
        }

        return nil
    }

    /// Fallback: if there's exactly one DCPAVServiceProxy, just use it.
    private func findSingleExternalAVService() -> IOAVServiceRef? {
        guard let matching = IOServiceMatching("DCPAVServiceProxy") else { return nil }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var services: [IOAVServiceRef] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            // Only consider entries that have EDID (i.e., connected external displays)
            if IORegistryEntryCreateCFProperty(service, "IODisplayEDID" as CFString, kCFAllocatorDefault, 0) != nil {
                if let avService = IOAVServiceCreateWithService(kCFAllocatorDefault, service) {
                    services.append(avService)
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        return services.count == 1 ? services.first : nil
    }
}
