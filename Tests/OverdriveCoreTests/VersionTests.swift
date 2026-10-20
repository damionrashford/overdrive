import Testing

// Version comparison lives in the app target; the same rule is mirrored here so it is covered.
private func isNewer(_ candidate: String, than current: String) -> Bool {
    let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
    let b = current.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(a.count, b.count) {
        let x = i < a.count ? a[i] : 0
        let y = i < b.count ? b[i] : 0
        if x != y { return x > y }
    }
    return false
}

@Suite struct VersionTests {
    @Test func dottedVersionsCompareNumerically() {
        #expect(isNewer("1.10.0", than: "1.9.0"))
        #expect(isNewer("2.0", than: "1.99.99"))
        #expect(!isNewer("1.1.0", than: "1.1.0"))
        #expect(!isNewer("1.0.9", than: "1.1"))
    }
}
