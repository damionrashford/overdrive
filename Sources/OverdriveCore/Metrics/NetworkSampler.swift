import Darwin
import Foundation
import SystemConfiguration

public struct NetworkInterfaceInfo: Sendable, Identifiable, Hashable {
    public var id: String { bsdName }
    public let bsdName: String
    public let displayName: String
    public let ipv4: String?
    public let bytesIn: UInt64
    public let bytesOut: UInt64
}

public struct NetworkSnapshot: Sendable {
    public var downPerSec: Double = 0
    public var upPerSec: Double = 0
    public var totalDown: UInt64 = 0
    public var totalUp: UInt64 = 0
    public var interfaces: [NetworkInterfaceInfo] = []

    public init() {}
}

public final class NetworkSampler {
    private var previous: (time: Double, down: UInt64, up: UInt64)?
    private var displayNames: [String: String] = [:]
    private var namesLoadedAt: Double = -.infinity

    public init() {}

    public func sample() -> NetworkSnapshot {
        let now = monotonicSeconds()
        if now - namesLoadedAt > 60 {
            displayNames = Self.loadDisplayNames()
            namesLoadedAt = now
        }
        let counters = Self.readCounters()
        let addresses = Self.ipv4Addresses()

        var snap = NetworkSnapshot()
        // Physical interfaces only: VPN tunnels (utun) re-carry traffic already counted on en*.
        for (name, c) in counters where Self.isPhysical(name) {
            snap.totalDown += c.inBytes
            snap.totalUp += c.outBytes
        }
        if let p = previous, now > p.time {
            let dt = now - p.time
            snap.downPerSec = Double(positiveDelta(snap.totalDown, p.down)) / dt
            snap.upPerSec = Double(positiveDelta(snap.totalUp, p.up)) / dt
        }
        previous = (now, snap.totalDown, snap.totalUp)

        // VM bridges (OrbStack, Docker, Parallels) carry no traffic of their own and only add noise.
        snap.interfaces = addresses.keys.filter { Self.isPhysical($0) || $0.hasPrefix("utun") }
            .sorted(by: Self.interfaceOrder).map { name in
            NetworkInterfaceInfo(
                bsdName: name,
                displayName: displayNames[name] ?? (name.hasPrefix("utun") ? "VPN Tunnel" : name),
                ipv4: addresses[name],
                bytesIn: counters[name]?.inBytes ?? 0,
                bytesOut: counters[name]?.outBytes ?? 0
            )
        }
        return snap
    }

    static func isPhysical(_ name: String) -> Bool {
        name.hasPrefix("en") || name.hasPrefix("pdp_ip")
    }

    private static func interfaceOrder(_ a: String, _ b: String) -> Bool {
        let rank = { (n: String) in isPhysical(n) ? 0 : 1 }
        return (rank(a), a.count, a) < (rank(b), b.count, b)
    }

    /// 64-bit per-interface byte counters via NET_RT_IFLIST2 (getifaddrs' if_data is 32-bit and wraps at 4 GB).
    private static func readCounters() -> [String: (inBytes: UInt64, outBytes: UInt64)] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return [:] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return [:] }

        var result: [String: (UInt64, UInt64)] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if info.ifm_flags & IFF_LOOPBACK == 0 {
                        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                        if if_indextoname(UInt32(info.ifm_index), &name) != nil {
                            let key = name.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                            result[key] = (info.ifm_data.ifi_ibytes, info.ifm_data.ifi_obytes)
                        }
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return result
    }

    private static func ipv4Addresses() -> [String: String] {
        var result: [String: String] = [:]
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [:] }
        defer { freeifaddrs(head) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let name = String(cString: entry.pointee.ifa_name)
                result[name] = host.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            }
        }
        return result
    }

    private static func loadDisplayNames() -> [String: String] {
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [:] }
        var names: [String: String] = [:]
        for interface in all {
            if let bsd = SCNetworkInterfaceGetBSDName(interface) as String?,
               let display = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? {
                names[bsd] = display
            }
        }
        return names
    }
}
