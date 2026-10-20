import Foundation
import Testing
@testable import OverdriveCore

@Suite struct MetricsTests {
    @Test func systemInfoDescribesThisMac() {
        let info = SystemInfo.current()
        #expect(info.physicalMemory > 1 << 30)
        #expect(info.logicalCores > 0)
        #expect(info.clusters.flatMap(\.cores).count == info.logicalCores)
        #expect(Set(info.clusters.flatMap(\.cores)) == Set(0..<info.logicalCores))
        #expect(info.bootTime < Date())
        #expect(!info.chip.isEmpty)
    }

    @Test func cpuLoadIsAFractionPerCore() throws {
        let sampler = CPUSampler()
        // Burn a little CPU so the delta is not empty.
        var x = 0.0
        let end = Date().addingTimeInterval(0.3)
        while Date() < end { x += sin(x) + 1 }
        let snap = sampler.sample()
        #expect(snap.cores.count == SystemInfo.current().logicalCores)
        #expect(snap.cores.allSatisfy { (0...1).contains($0) })
        #expect(snap.total > 0 && snap.total <= 1)
        #expect(x > 0)
    }

    @Test func memoryAddsUp() {
        let snap = MemorySampler().sample()
        #expect(snap.total > 0)
        #expect(snap.used > 0 && snap.used <= snap.total)
        #expect(snap.used + snap.cached + snap.free == snap.total || snap.free == 0)
        #expect((0...1).contains(snap.pressureFraction))
    }

    @Test func gpuStatsAreReadable() {
        let snap = GPUSampler().sample()
        #expect(snap.available)
        #expect((0...1).contains(snap.device))
    }

    @Test func diskCountersAndVolumes() {
        let sampler = DiskSampler()
        let io = sampler.sampleIO()
        #expect(io.totalRead > 0)
        let volumes = DiskSampler.volumes()
        let root = volumes.first { $0.isRoot }
        #expect(root != nil)
        if let root {
            #expect(root.total > 0)
            #expect(root.available <= root.total)
            #expect(root.free <= root.available)
        }
    }

    @Test func networkSees64BitCounters() {
        let sampler = NetworkSampler()
        _ = sampler.sample()
        Thread.sleep(forTimeInterval: 0.2)
        let snap = sampler.sample()
        #expect(snap.totalDown > 0)
        #expect(snap.downPerSec >= 0)
    }

    @Test func processesIncludeThisTestRunner() {
        let sampler = ProcessSampler()
        _ = sampler.sample()
        Thread.sleep(forTimeInterval: 0.2)
        let processes = sampler.sample()
        let me = processes.first { $0.pid == getpid() }
        #expect(me != nil)
        #expect((me?.memory ?? 0) > 0)
        #expect((me?.threads ?? 0) > 0)
        #expect(processes.count > 10)
    }

    @Test func outermostAppBundle() {
        let path = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        #expect(ProcessSampler.outermostApp(in: path) == "/Applications/Google Chrome.app")
        #expect(ProcessSampler.outermostApp(in: "/usr/bin/zsh") == nil)
    }

    @Test func formatting() {
        #expect(Fmt.memory(1536 * 1024 * 1024) == "1.50 GB")
        #expect(Fmt.storage(250_000_000_000) == "250 GB")
        #expect(Fmt.storage(512) == "512 B")
        #expect(Fmt.rate(12_300) == "12.3 KB/s")
        #expect(Fmt.duration(90_061) == "1d 1h")
        #expect(Fmt.percent(0.256) == "26%")
    }

    @Test func engineProducesASample() async {
        let engine = SamplerEngine()
        let sample = await engine.sample(includeVolumes: true)
        #expect(sample.volumes?.isEmpty == false)
        #expect(sample.memory.total > 0)
    }
}
