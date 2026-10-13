import Darwin
import Foundation

/// v0.1 accepts local names or private/link-local/loopback addresses only.
public enum LocalAddress {
    public static func isAllowed(_ address: String) -> Bool {
        guard !address.isEmpty else { return false }
        let name = address.lowercased()
        if name == "localhost" { return true }
        if name.hasSuffix(".local"), name.count > 6, name.count <= 253 {
            let labels = name.split(separator: ".", omittingEmptySubsequences: false)
            return labels.allSatisfy { label in
                !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-"
                    && label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
            }
        }
        let components = address.split(separator: ".", omittingEmptySubsequences: false)
        if components.count == 4 {
            let octets = components.compactMap { part -> UInt8? in
                guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
                return UInt8(part)
            }
            if octets.count == 4 { return isAllowedIPv4(Data(octets)) }
        }
        let scoped = address.split(separator: "%", omittingEmptySubsequences: false)
        guard scoped.count <= 2 else { return false }
        if scoped.count == 2 {
            guard !scoped[1].isEmpty,
                scoped[1].utf8.allSatisfy({
                    (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                })
            else { return false }
        }
        var ipv6 = in6_addr()
        guard inet_pton(AF_INET6, String(scoped[0]), &ipv6) == 1 else { return false }
        return withUnsafeBytes(of: ipv6) { isAllowedIPv6(Data($0)) }
    }
    public static func isAllowedIPv4(_ bytes: Data) -> Bool {
        let b = Array(bytes)
        guard b.count == 4 else { return false }
        return b[0] == 10 || b[0] == 127 || (b[0] == 172 && (16...31).contains(b[1]))
            || (b[0] == 192 && b[1] == 168) || (b[0] == 169 && b[1] == 254)
    }
    public static func isAllowedIPv6(_ bytes: Data) -> Bool {
        let b = Array(bytes)
        guard b.count == 16 else { return false }
        if b.prefix(15).allSatisfy({ $0 == 0 }), b[15] == 1 { return true }
        if b[0] & 0xFE == 0xFC { return true }  // Unique local.
        if b[0] == 0xFE, b[1] & 0xC0 == 0x80 { return true }  // Link-local.
        if b.prefix(10).allSatisfy({ $0 == 0 }), b[10] == 255, b[11] == 255 {
            return isAllowedIPv4(Data(b.suffix(4)))
        }
        return false
    }
}
