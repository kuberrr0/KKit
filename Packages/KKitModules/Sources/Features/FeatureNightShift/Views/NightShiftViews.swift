import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// The Night Shift row in the KKit menu: on/off and the intensity slider.
struct NightShiftMenuSection: View {
    let controller: NightShiftController

    var body: some View {
        HStack(spacing: KKSpacing.s) {
            Button {
                controller.toggle()
            } label: {
                Image(systemName: controller.isActive ? "moon.stars.fill" : "moon.stars")
                    .foregroundStyle(controller.isActive ? Color.orange : Color.secondary)
                    .frame(width: 20)
            }
            .buttonStyle(.borderless)
            .help(controller.isActive ? Text("Turn Night Shift off") : Text("Turn Night Shift on"))
            .accessibilityLabel(Text("Night Shift"))
            .accessibilityValue(controller.isActive ? Text("On") : Text("Off"))

            NightShiftIntensitySlider(controller: controller)
        }
    }
}

/// 0–200%. Reads and writes through the controller so dragging turns the tint on.
struct NightShiftIntensitySlider: View {
    let controller: NightShiftController
    @State private var value: Double?

    var body: some View {
        let binding = Binding<Double>(
            get: { value ?? controller.currentIntensity },
            set: { newValue in
                value = newValue
                controller.setIntensity(newValue)
            }
        )
        HStack(spacing: KKSpacing.s) {
            Slider(value: binding, in: 0...2)
                .labelsHidden()
                .accessibilityLabel(Text("Night Shift intensity"))
                .accessibilityValue(Text(KKFormat.percent(binding.wrappedValue)))
            Text(KKFormat.percent(binding.wrappedValue))
                .font(.callout.monospacedDigit())
                .foregroundStyle(binding.wrappedValue > 1 ? Color.orange : Color.secondary)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .onChange(of: controller.currentIntensity) { _, _ in value = nil }
    }
}

extension NightShiftController {
    var currentIntensity: Double { settingsIntensity }
}

/// Settings › Night Shift.
struct NightShiftSettingsView: View {
    let controller: NightShiftController
    let display: any DisplayService
    let location: any LocationService

    @Setting(NightShiftSettings.mode) private var mode
    @Setting(NightShiftSettings.extraDim) private var extraDim
    @Setting(NightShiftSettings.schedule) private var schedule
    @Setting(NightShiftSettings.customStart) private var customStart
    @Setting(NightShiftSettings.customEnd) private var customEnd
    @Setting(NightShiftSettings.coordinate) private var coordinate
    @Setting(NightShiftSettings.transitionSeconds) private var transitionSeconds
    @Setting(NightShiftSettings.disabledDisplays) private var disabledDisplays
    @Setting(NightShiftSettings.disabledApps) private var disabledApps

    @State private var locationError: String?
    @State private var isLocating = false

    var body: some View {
        Group {
            tint
            scheduleSection
            exceptions
        }
    }

    @ViewBuilder
    private var tint: some View {
        Toggle(String(localized: "Night Shift on"), isOn: Binding(
            get: { controller.isActive },
            set: { controller.setOn($0) }
        ))
        LabeledContent(String(localized: "Intensity")) {
            NightShiftIntensitySlider(controller: controller)
                .frame(maxWidth: 260)
        }
        Text("Above 100% goes beyond what macOS Night Shift allows.")
            .font(.caption)
            .foregroundStyle(.secondary)
        Picker(String(localized: "Mode"), selection: $mode) {
            ForEach(NightShiftMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        LabeledContent(String(localized: "Extra dim")) {
            HStack {
                Slider(value: $extraDim, in: 0...0.8)
                    .frame(maxWidth: 220)
                    .accessibilityLabel(Text("Extra dim"))
                Text(KKFormat.percent(extraDim))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 40, alignment: .trailing)
            }
        }
        Picker(String(localized: "Fade"), selection: $transitionSeconds) {
            Text("None").tag(0.0)
            Text("Quick (1 s)").tag(1.0)
            Text("Slow (5 s)").tag(5.0)
            Text("Very slow (30 s)").tag(30.0)
        }
    }

    @ViewBuilder
    private var scheduleSection: some View {
        Picker(String(localized: "Schedule"), selection: $schedule) {
            ForEach(NightShiftScheduleKind.allCases) { kind in
                Text(kind.title).tag(kind)
            }
        }
        if schedule == .custom || (schedule == .sunset && coordinate == nil) {
            HStack {
                DatePicker(String(localized: "From"), selection: timeBinding($customStart), displayedComponents: .hourAndMinute)
                DatePicker(String(localized: "to"), selection: timeBinding($customEnd), displayedComponents: .hourAndMinute)
            }
        }
        if schedule == .sunset {
            HStack {
                if let coordinate, let sun = SolarCalculator.sunTimes(on: Date(), latitude: coordinate.latitude, longitude: coordinate.longitude) {
                    Text("Today: sunset \(sun.sunset.formatted(date: .omitted, time: .shortened)), sunrise \(sun.sunrise.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Set your location to use sunset and sunrise. Until then the times above are used.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(coordinate == nil ? String(localized: "Use My Location") : String(localized: "Update Location")) {
                    locate()
                }
                .disabled(isLocating)
            }
            .font(.callout)
            if let locationError {
                Text(locationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        if controller.isPaused, let until = controller.pausedUntil {
            HStack {
                Text("Paused until \(until.formatted(date: .omitted, time: .shortened))")
                Spacer()
                Button(String(localized: "Resume")) { controller.resume() }
            }
        } else {
            Button(String(localized: "Pause for an Hour")) { controller.pause(for: 3600) }
        }
    }

    @ViewBuilder
    private var exceptions: some View {
        let displays = display.displays
        if displays.count > 1 || !disabledDisplays.isEmpty {
            Text("Displays").font(.headline).padding(.top, KKSpacing.s)
            ForEach(displays) { info in
                Toggle(info.name, isOn: Binding(
                    get: { !disabledDisplays.contains(info.stableID) },
                    set: { on in
                        var updated = disabledDisplays.filter { $0 != info.stableID }
                        if !on { updated.append(info.stableID) }
                        disabledDisplays = updated
                    }
                ))
            }
        }
        Text("Turn off while these apps are in front").font(.headline).padding(.top, KKSpacing.s)
        ForEach(disabledApps, id: \.self) { bundleID in
            KKRow(Self.appName(bundleID), symbol: "app") {
                Button {
                    disabledApps.removeAll { $0 == bundleID }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Remove \(Self.appName(bundleID))"))
            }
        }
        Menu(String(localized: "Add App…")) {
            ForEach(Self.runningApps().filter { !disabledApps.contains($0.id) }) { app in
                Button(app.name) { disabledApps.append(app.id) }
            }
        }
        .fixedSize()
    }

    /// Minutes after midnight as a `Date` today, for `DatePicker`.
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private func locate() {
        isLocating = true
        locationError = nil
        let location = self.location
        let coordinateBinding = $coordinate
        Task { @MainActor in
            do {
                coordinateBinding.wrappedValue = try await location.currentCoordinate()
            } catch {
                locationError = error.localizedDescription
            }
            isLocating = false
        }
    }

    struct RunningApp: Identifiable {
        let id: String
        let name: String
    }

    static func runningApps() -> [RunningApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningApp? in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return nil }
                return RunningApp(id: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func appName(_ bundleID: String) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? bundleID
    }
}
