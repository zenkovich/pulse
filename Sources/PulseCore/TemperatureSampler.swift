import Foundation
import IOKit

/// Die temperatures from the HID thermal sensors (the private IOHIDEventSystemClient API, resolved at run time).
/// Every lookup is optional: on Macs without these sensors the temperature simply isn't shown.
public final class TemperatureSampler {
    private typealias CreateClient = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Int32
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloat = @convention(c) (AnyObject, Int32) -> Double

    private static let temperatureEvent: Int64 = 15            // kIOHIDEventTypeTemperature
    private static let temperatureField = Int32(15 << 16)      // IOHIDEventFieldBase(kIOHIDEventTypeTemperature)

    enum Group { case chip, gpu, ssd, battery }

    private var client: AnyObject?
    private var sensors: [(service: AnyObject, group: Group)] = []
    private var copyEvent: CopyEvent?
    private var getFloat: GetFloat?

    public init() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let createSym = dlsym(handle, "IOHIDEventSystemClientCreate"),
              let matchSym = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
              let servicesSym = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
              let propertySym = dlsym(handle, "IOHIDServiceClientCopyProperty"),
              let eventSym = dlsym(handle, "IOHIDServiceClientCopyEvent"),
              let floatSym = dlsym(handle, "IOHIDEventGetFloatValue") else { return }
        let create = unsafeBitCast(createSym, to: CreateClient.self)
        let setMatching = unsafeBitCast(matchSym, to: SetMatching.self)
        let copyServices = unsafeBitCast(servicesSym, to: CopyServices.self)
        let copyProperty = unsafeBitCast(propertySym, to: CopyProperty.self)
        copyEvent = unsafeBitCast(eventSym, to: CopyEvent.self)
        getFloat = unsafeBitCast(floatSym, to: GetFloat.self)

        guard let client = create(kCFAllocatorDefault)?.takeRetainedValue() else { return }
        self.client = client
        // Vendor page 0xff00, usage 5: temperature sensors.
        _ = setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        guard let services = copyServices(client)?.takeRetainedValue() as? [AnyObject] else { return }
        for service in services {
            guard let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String,
                  let group = Self.group(for: name) else { continue }
            sensors.append((service, group))
        }
    }

    public var isAvailable: Bool { !sensors.isEmpty }

    /// Sensor names: "PMU tdie*" on M3/M4, "pACC/eACC MTR Temp Sensor*" on M1/M2.
    static func group(for name: String) -> Group? {
        if name.contains("tdie") || name.contains("ACC MTR Temp") || name.contains("SOC MTR Temp") { return .chip }
        if name.contains("GPU MTR Temp") { return .gpu }
        if name.hasPrefix("NAND") { return .ssd }
        if name.contains("battery") { return .battery }
        return nil
    }

    public func sample() -> Temperatures {
        guard let copyEvent, let getFloat else { return Temperatures() }
        var hottest: [Group: Double] = [:]
        for sensor in sensors {
            guard let event = copyEvent(sensor.service, Self.temperatureEvent, 0, 0)?.takeRetainedValue() else { continue }
            let value = getFloat(event, Self.temperatureField)
            // Idle sensors sometimes report 0 or garbage.
            guard value > 1, value < 150 else { continue }
            hottest[sensor.group] = max(hottest[sensor.group] ?? 0, value)
        }
        return Temperatures(chip: hottest[.chip], gpu: hottest[.gpu], ssd: hottest[.ssd], battery: hottest[.battery])
    }
}
