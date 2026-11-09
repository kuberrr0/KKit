# Stats

CPU, memory, disk, network, battery and thermal state. DESIGN.md §3.3.

- **Surfaces:** optional menu bar items per metric (CPU sparkline, memory %, network
  rates, free disk, battery) with a details popover; a stats strip in the KKit menu;
  a Stats page in the expanded Island; Island alerts for low battery, high memory
  pressure and low disk space; the `stats.copySummary` command.
- **Sampling is demand-driven:** `SystemInfoService` samples only while a menu bar item
  is shown, the KKit menu or a details popover is open, or the Island page is visible.
  Battery and memory-pressure alerts are events (IOKit power source notifications and a
  memory-pressure dispatch source), and free disk space is checked twice an hour.
- **APIs:** `SystemInfoService` (`host_processor_info`, `host_statistics64`, `sysctl`,
  `getifaddrs`, `libproc`, `URLResourceValues`), `PowerService` (IOKit power sources,
  `AppleSmartBattery` for cycle count and health).
- **Permissions:** none.
- **Limits:** temperatures and fans (private SMC) and the public IP aren't in v1. Network
  rates count physical interfaces (`en*`) only. Processes owned by other users (root
  daemons) don't appear in the top-process list.
