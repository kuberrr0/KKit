import Darwin
import Foundation
import KKitServicesAPI

/// Reads CPU, memory, disk, network and process counters. An actor so sampling runs off
/// the main thread; it keeps the previous counters to turn them into rates.
actor SystemSampler {
    private struct CoreTicks {
        var user: UInt64
        var system: UInt64
        var idle: UInt64
        var nice: UInt64

        var busy: UInt64 { user + system + nice }
        var total: UInt64 { busy + idle }
    }

    private let hostPort = mach_host_self()
    private let pageSize = UInt64(getpagesize())
    private let timebase: (numer: UInt64, denom: UInt64)

    private var previousCores: [CoreTicks]?
    private var previousNetwork: (date: Date, counters: [String: (rx: UInt32, tx: UInt32)])?
    private var previousProcesses: (date: Date, cpuTime: [pid_t: UInt64])?

    init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        timebase = (UInt64(max(info.numer, 1)), UInt64(max(info.denom, 1)))
    }

    func sample(includeProcesses: Bool) -> SystemSample {
        let now = Date()
        return SystemSample(
            date: now,
            cpu: cpu(),
            memory: memory(),
            disk: disk(),
            network: network(now: now),
            thermal: Self.thermal(),
            topProcesses: includeProcesses ? processes(now: now) : []
        )
    }

    // MARK: CPU

    private func cpu() -> CPUSample {
        guard let cores = readCoreTicks() else { return CPUSample() }
        defer { previousCores = cores }
        guard let previous = previousCores, previous.count == cores.count else {
            return CPUSample()
        }
        var perCore: [Double] = []
        var busy: UInt64 = 0, user: UInt64 = 0, system: UInt64 = 0, total: UInt64 = 0
        for (now, before) in zip(cores, previous) {
            let coreTotal = now.total &- before.total
            let coreBusy = now.busy &- before.busy
            perCore.append(coreTotal == 0 ? 0 : min(1, Double(coreBusy) / Double(coreTotal)))
            busy += coreBusy
            user += (now.user &- before.user) + (now.nice &- before.nice)
            system += now.system &- before.system
            total += coreTotal
        }
        guard total > 0 else { return CPUSample(perCore: perCore) }
        return CPUSample(
            total: min(1, Double(busy) / Double(total)),
            user: Double(user) / Double(total),
            system: Double(system) / Double(total),
            perCore: perCore
        )
    }

    private func readCoreTicks() -> [CoreTicks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(hostPort, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info
        else { return nil }
        // The array is allocated in our address space by the kernel; munmap releases it
        // without needing the task port.
        defer { munmap(UnsafeMutableRawPointer(info), Int(infoCount) * MemoryLayout<integer_t>.stride) }
        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(cpuCount)).map { core in
            let base = core * stride
            func ticks(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[base + Int(state)])) }
            return CoreTicks(
                user: ticks(CPU_STATE_USER),
                system: ticks(CPU_STATE_SYSTEM),
                idle: ticks(CPU_STATE_IDLE),
                nice: ticks(CPU_STATE_NICE)
            )
        }
    }

    // MARK: Memory

    private func memory() -> MemorySample {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else { return MemorySample(total: total) }

        let app = UInt64(stats.internal_page_count &- min(stats.internal_page_count, stats.purgeable_count)) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        return MemorySample(
            total: total,
            used: min(total, app + wired + compressed),
            app: app,
            wired: wired,
            compressed: compressed,
            swapUsed: Self.swapUsed(),
            pressure: Self.memoryPressure()
        )
    }

    private static func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    static func memoryPressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        return MemoryPressure(rawValue: Int(level)) ?? .normal
    }

    // MARK: Disk

    private func disk() -> DiskSample {
        let root = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? root.resourceValues(forKeys: keys) else { return DiskSample() }
        return DiskSample(
            name: values.volumeLocalizedName ?? "Macintosh HD",
            totalBytes: Int64(values.volumeTotalCapacity ?? 0),
            availableBytes: values.volumeAvailableCapacityForImportantUsage ?? 0
        )
    }

    // MARK: Network

    private func network(now: Date) -> NetworkSample {
        var counters: [String: (rx: UInt32, tx: UInt32)] = [:]
        var localIP: String?

        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return NetworkSample() }
        defer { freeifaddrs(addresses) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let entry = current.pointee
            cursor = entry.ifa_next
            let name = String(cString: entry.ifa_name)
            // Physical interfaces only (Wi-Fi, Ethernet); VPN tunnels would count twice.
            guard name.hasPrefix("en"), let address = entry.ifa_addr else { continue }
            let family = Int32(address.pointee.sa_family)
            if family == AF_LINK, let data = entry.ifa_data {
                let stats = data.assumingMemoryBound(to: if_data.self).pointee
                counters[name] = (stats.ifi_ibytes, stats.ifi_obytes)
            } else if family == AF_INET, localIP == nil || name == "en0" {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    localIP = host.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                }
            }
        }

        defer { previousNetwork = (now, counters) }
        guard let previous = previousNetwork else { return NetworkSample(localIP: localIP) }
        let seconds = now.timeIntervalSince(previous.date)
        guard seconds > 0 else { return NetworkSample(localIP: localIP) }
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for (name, counter) in counters {
            guard let before = previous.counters[name] else { continue }
            // The 32-bit counters wrap at 4 GB; &- gives the right difference across one wrap.
            received += UInt64(counter.rx &- before.rx)
            sent += UInt64(counter.tx &- before.tx)
        }
        return NetworkSample(
            bytesInPerSecond: Double(received) / seconds,
            bytesOutPerSecond: Double(sent) / seconds,
            localIP: localIP
        )
    }

    // MARK: Processes

    private func processes(now: Date) -> [ProcessSample] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }

        var cpuTime: [pid_t: UInt64] = [:]
        var info = proc_taskinfo()
        let infoSize = Int32(MemoryLayout<proc_taskinfo>.size)
        for pid in pids.prefix(Int(count)) where pid > 0 {
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, infoSize) == infoSize else { continue }
            cpuTime[pid] = info.pti_total_user + info.pti_total_system
        }

        defer { previousProcesses = (now, cpuTime) }
        guard let previous = previousProcesses else { return [] }
        let elapsed = now.timeIntervalSince(previous.date)
        guard elapsed > 0 else { return [] }

        var samples: [ProcessSample] = []
        for (pid, time) in cpuTime {
            guard let before = previous.cpuTime[pid], time > before else { continue }
            // Task times are in Mach absolute time units.
            let nanoseconds = Double((time - before) * timebase.numer / timebase.denom)
            let share = nanoseconds / (elapsed * 1_000_000_000)
            guard share >= 0.005 else { continue }
            samples.append(ProcessSample(pid: pid, name: Self.processName(pid), cpu: share))
        }
        return Array(samples.sorted { $0.cpu > $1.cpu }.prefix(8))
    }

    private static func processName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "PID \(pid)" }
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    // MARK: Thermal

    private static func thermal() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }
}
