import Darwin
import Foundation
import IOKit

/// Thin wrappers over sysctl and the IORegistry, shared by every sampler.
enum Sysctl {
    static func integer(_ name: String) -> Int64? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { return nil }
        switch size {
        case 4:
            var value: Int32 = 0
            var s = 4
            guard sysctlbyname(name, &value, &s, nil, 0) == 0 else { return nil }
            return Int64(value)
        case 8:
            var value: Int64 = 0
            var s = 8
            guard sysctlbyname(name, &value, &s, nil, 0) == 0 else { return nil }
            return value
        default:
            return nil
        }
    }

    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    static func raw<T>(_ name: String, as type: T.Type, initial: T) -> T? {
        var value = initial
        var size = MemoryLayout<T>.size
        let status = withUnsafeMutableBytes(of: &value) { sysctlbyname(name, $0.baseAddress, &size, nil, 0) }
        return status == 0 ? value : nil
    }
}

enum IOReg {
    static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    static func string(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let d = value as? Data {
            let s = String(decoding: d.prefix { $0 != 0 }, as: UTF8.self)
            return s.isEmpty ? nil : s
        }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let d = value as? Data, !d.isEmpty {
            var v: UInt64 = 0
            for (i, byte) in d.prefix(8).enumerated() { v |= UInt64(byte) << (8 * UInt64(i)) }
            return Int(v)
        }
        return nil
    }

    static func uint64(_ value: Any?) -> UInt64 {
        (value as? NSNumber)?.uint64Value ?? 0
    }

    static func forEachService(matching className: String, _ body: (io_registry_entry_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { break }
            body(entry)
            IOObjectRelease(entry)
        }
    }

    static func forEachChild(ofPath path: String, plane: String, _ body: (io_registry_entry_t) -> Void) {
        let parent = IORegistryEntryFromPath(kIOMainPortDefault, path)
        guard parent != 0 else { return }
        defer { IOObjectRelease(parent) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(parent, plane, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { break }
            body(entry)
            IOObjectRelease(entry)
        }
    }
}

/// Monotonic seconds, for turning counter deltas into rates.
func monotonicSeconds() -> Double {
    Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
}

/// Counter delta that treats a reset (counter went backwards) as zero rather than a huge number.
func positiveDelta(_ now: UInt64, _ before: UInt64) -> UInt64 {
    now >= before ? now - before : 0
}
