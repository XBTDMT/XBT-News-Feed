@preconcurrency import Foundation
import IOKit.ps

@MainActor
final class PowerMonitor: ObservableObject {
    @Published var isOnACPower: Bool = true
    @Published var isLowPowerMode: Bool = false
    /// 0.0 ... 1.0, nil when no battery is present or the level is unknown.
    @Published var batteryLevel: Double? = nil
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?

    static let shared = PowerMonitor()

    /// Test/measurement hook: `PULSEFEED_FORCE_TIER=ac|battery|critical` pins the tier.
    nonisolated static let forcedTier: PowerTier? = {
        switch ProcessInfo.processInfo.environment["PULSEFEED_FORCE_TIER"]?.lowercased() {
        case "ac": return .ac
        case "battery": return .battery
        case "critical": return .critical
        default: return nil
        }
    }()

    static let criticalLevel = 0.20

    init() {
        updatePowerState()
        startMonitoring()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateChanged),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
    }

    /// ac: plugged in, no Low Power Mode. critical: on battery and (below 20% or Low Power Mode).
    /// battery: everything else (including Low Power Mode while plugged in).
    var tier: PowerTier {
        if let forced = Self.forcedTier { return forced }
        if isOnACPower && !isLowPowerMode { return .ac }
        if !isOnACPower && (isLowPowerMode || (batteryLevel ?? 1.0) < Self.criticalLevel) { return .critical }
        return .battery
    }

    var shouldThrottle: Bool { tier != .ac }

    private func updatePowerState() {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let source = IOPSGetProvidingPowerSourceType(snapshot).takeRetainedValue() as String
        isOnACPower = (source == kIOPSACPowerValue)
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        batteryLevel = Self.readBatteryLevel(snapshot)
    }

    private static func readBatteryLevel(_ snapshot: CFTypeRef) -> Double? {
        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  (info[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = info[kIOPSCurrentCapacityKey] as? Int,
                  let max = info[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            return Double(current) / Double(max)
        }
        return nil
    }

    private func startMonitoring() {
        let callback: IOPowerSourceCallbackType = { context in
            guard let context = context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { monitor.updatePowerState() }
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    @objc private func powerStateChanged() {
        updatePowerState()
    }

    deinit {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }
}
