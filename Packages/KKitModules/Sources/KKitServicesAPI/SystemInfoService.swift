import Foundation

public struct CPUSample: Sendable, Equatable {
    /// 0…1 across all cores.
    public var total: Double
    public var user: Double
    public var system: Double
    /// 0…1 per core.
    public var perCore: [Double]

    public init(total: Double = 0, user: Double = 0, system: Double = 0, perCore: [Double] = []) {
        self.total = total
        self.user = user
        self.system = system
        self.perCore = perCore
    }
}

public enum MemoryPressure: Int, Sendable, Comparable {
    case normal = 1
    case warning = 2
    case critical = 4

    public static func < (lhs: MemoryPressure, rhs: MemoryPressure) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct MemorySample: Sendable, Equatable {
    public var total: UInt64
    /// App + wired + compressed, as Activity Monitor's "Memory Used".
    public var used: UInt64
    public var app: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    public var swapUsed: UInt64
    public var pressure: MemoryPressure

    public init(total: UInt64 = 0, used: UInt64 = 0, app: UInt64 = 0, wired: UInt64 = 0,
                compressed: UInt64 = 0, swapUsed: UInt64 = 0, pressure: MemoryPressure = .normal) {
        self.total = total
        self.used = used
        self.app = app
        self.wired = wired
        self.compressed = compressed
        self.swapUsed = swapUsed
        self.pressure = pressure
    }

    public var usedFraction: Double {
        total == 0 ? 0 : Double(used) / Double(total)
    }
}

public struct DiskSample: Sendable, Equatable {
    public var name: String
    public var totalBytes: Int64
    public var availableBytes: Int64

    public init(name: String = "", totalBytes: Int64 = 0, availableBytes: Int64 = 0) {
        self.name = name
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
    }

    public var usedFraction: Double {
        totalBytes == 0 ? 0 : 1 - Double(availableBytes) / Double(totalBytes)
    }
}

public struct NetworkSample: Sendable, Equatable {
    public var bytesInPerSecond: Double
    public var bytesOutPerSecond: Double
    public var localIP: String?

    public init(bytesInPerSecond: Double = 0, bytesOutPerSecond: Double = 0, localIP: String? = nil) {
        self.bytesInPerSecond = bytesInPerSecond
        self.bytesOutPerSecond = bytesOutPerSecond
        self.localIP = localIP
    }
}

public struct ProcessSample: Sendable, Equatable, Identifiable {
    public var pid: Int32
    public var name: String
    /// Share of one core, so 2.0 means two full cores.
    public var cpu: Double

    public var id: Int32 { pid }

    public init(pid: Int32, name: String, cpu: Double) {
        self.pid = pid
        self.name = name
        self.cpu = cpu
    }
}

public enum ThermalLevel: Int, Sendable, Equatable {
    case nominal, fair, serious, critical
}

public struct SystemSample: Sendable, Equatable {
    public var date: Date
    public var cpu: CPUSample
    public var memory: MemorySample
    public var disk: DiskSample
    public var network: NetworkSample
    public var thermal: ThermalLevel
    /// Highest CPU users first; empty unless a subscriber asked for processes.
    public var topProcesses: [ProcessSample]

    public init(
        date: Date = Date(),
        cpu: CPUSample = CPUSample(),
        memory: MemorySample = MemorySample(),
        disk: DiskSample = DiskSample(),
        network: NetworkSample = NetworkSample(),
        thermal: ThermalLevel = .nominal,
        topProcesses: [ProcessSample] = []
    ) {
        self.date = date
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.network = network
        self.thermal = thermal
        self.topProcesses = topProcesses
    }
}

/// CPU, memory, disk, network and thermal sampling. **Demand-driven**: it samples
/// only while at least one stream is open, at the shortest interval asked for.
@MainActor
public protocol SystemInfoService: AnyObject {
    func samples(every interval: Duration, includeProcesses: Bool) -> AsyncStream<SystemSample>
    /// The current memory pressure, then every change (a kernel event, not polling).
    func memoryPressureUpdates() -> AsyncStream<MemoryPressure>
}
