import Foundation
import IOKit

/// Reads the System Management Controller through the public IOKit user-client API
/// (`IOServiceOpen` on AppleSMC, selector 2). No root is needed outside the App Sandbox.
public final class SMCReader {
    // Matches the C SMCParamStruct the kernel expects, 80 bytes including padding.
    private struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
    private struct Limit { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    private struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0; var pad: (UInt8, UInt8, UInt8) = (0, 0, 0) }
    private struct Param {
        var key: UInt32 = 0
        var vers = Version()
        var limit = Limit()
        var keyInfo = KeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var pad: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private enum Selector: UInt8 { case readKey = 5, keyFromIndex = 8, keyInfo = 9 }

    public struct Key: Hashable, Sendable {
        public let name: String
        public let type: String
        public let size: Int
    }

    private var connection: io_connect_t = 0
    private var infoCache: [UInt32: KeyInfo] = [:]

    /// True when the SMC user client can be opened at all (false inside the App Sandbox).
    public static var isAvailable: Bool {
        guard let reader = SMCReader() else { return false }
        return reader.readFloat("#KEY") != nil || reader.keyCount() > 0
    }

    public init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    private static func code(_ s: String) -> UInt32 { s.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) } }

    private static func name(_ v: UInt32) -> String {
        String(bytes: [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)], encoding: .ascii) ?? "????"
    }

    private func call(_ input: inout Param) -> Param? {
        var output = Param()
        var size = MemoryLayout<Param>.size
        let r = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<Param>.size, &output, &size)
        return r == KERN_SUCCESS && output.result == 0 ? output : nil
    }

    private func info(for key: UInt32) -> KeyInfo? {
        if let cached = infoCache[key] { return cached }
        var p = Param()
        p.key = key
        p.data8 = Selector.keyInfo.rawValue
        guard let out = call(&p) else { return nil }
        infoCache[key] = out.keyInfo
        return out.keyInfo
    }

    public func keyCount() -> Int {
        guard let bytes = readBytes("#KEY") else { return 0 }
        return Int(bytes.reduce(0) { $0 << 8 | UInt32($1) })
    }

    public func key(at index: Int) -> Key? {
        var p = Param()
        p.data8 = Selector.keyFromIndex.rawValue
        p.data32 = UInt32(index)
        guard let out = call(&p), let info = info(for: out.key) else { return nil }
        return Key(name: Self.name(out.key), type: Self.name(info.dataType), size: Int(info.dataSize))
    }

    public func allKeys() -> [Key] {
        (0..<keyCount()).compactMap { key(at: $0) }
    }

    public func readBytes(_ name: String) -> [UInt8]? {
        let key = Self.code(name)
        guard let info = info(for: key), info.dataSize > 0, info.dataSize <= 32 else { return nil }
        var p = Param()
        p.key = key
        p.keyInfo = info
        p.data8 = Selector.readKey.rawValue
        guard let out = call(&p) else { return nil }
        return withUnsafeBytes(of: out.bytes) { Array($0.prefix(Int(info.dataSize))) }
    }

    /// Reads a key as a number, decoding the SMC's common float and integer encodings.
    public func readFloat(_ name: String) -> Double? {
        let key = Self.code(name)
        guard let info = info(for: key), let bytes = readBytes(name) else { return nil }
        switch Self.name(info.dataType) {
        case "flt " where bytes.count == 4:
            return Double(Float(bitPattern: UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24))
        case "ui8 " where bytes.count == 1:
            return Double(bytes[0])
        case "ui16" where bytes.count == 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32" where bytes.count == 4:
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        case "sp78" where bytes.count == 2:
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case "fpe2" where bytes.count == 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        default:
            return nil
        }
    }
}
