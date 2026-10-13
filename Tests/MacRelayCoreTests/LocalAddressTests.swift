import Testing

@testable import MacRelayCore

@Suite
struct LocalAddressTests {
    @Test
    func onlyLocalNamesAndAddressesAreAllowed() {
        for value in [
            "Mac-mini.local", "localhost", "192.168.1.12", "10.0.0.4", "172.16.0.1",
            "172.31.255.255", "169.254.2.3", "127.0.0.1", "::1", "fe80::1%en0", "fd00::2",
            "::ffff:192.168.0.4",
        ] {
            #expect(LocalAddress.isAllowed(value), "Expected a local address")
        }
        for value in [
            "", "example.com", "example.local.evil", ".local", "bad..local", "8.8.8.8", "0.0.0.0",
            "224.0.0.1", "192.168.1.999", "172.15.0.1", "172.32.0.1", "100.64.0.1",
            "2001:4860:4860::8888", "::", "fe80::1%", "192.168.1.1/path",
        ] {
            #expect(!LocalAddress.isAllowed(value), "Expected address rejection")
        }
    }
}
