import Foundation

public struct SystemSample: Sendable {
    public var cpu: CPUSnapshot
    public var memory: MemorySnapshot
    public var gpu: GPUSnapshot
    public var diskIO: DiskIOSnapshot
    public var volumes: [VolumeInfo]?
    public var network: NetworkSnapshot
    public var power: PowerSnapshot
    public var processes: [ProcessSample]
    public var thermal: ProcessInfo.ThermalState
    public var sensors: SensorSnapshot
}

/// Owns the stateful samplers off the main thread; each call returns deltas since the previous call.
public actor SamplerEngine {
    private let cpu = CPUSampler()
    private let memory = MemorySampler()
    private let gpu = GPUSampler()
    private let disk = DiskSampler()
    private let network = NetworkSampler()
    private let power = PowerSampler()
    private let processes = ProcessSampler()
    private let sensors: SensorSampler?

    public init(chip: String) {
        sensors = Capabilities.current.canReadSensors ? SensorSampler(chip: chip) : nil
    }

    public var sensorsAvailable: Bool { sensors?.isAvailable ?? false }

    public func sample(includeVolumes: Bool) -> SystemSample {
        SystemSample(
            cpu: cpu.sample(),
            memory: memory.sample(),
            gpu: gpu.sample(),
            diskIO: disk.sampleIO(),
            volumes: includeVolumes ? DiskSampler.volumes() : nil,
            network: network.sample(),
            power: power.sample(),
            processes: processes.sample(),
            thermal: ProcessInfo.processInfo.thermalState,
            sensors: sensors?.sample() ?? SensorSnapshot()
        )
    }
}
