import Foundation

enum BatteryAlertLevel: Equatable {
    case normal
    case warning
    case critical

    static func resolve(from battery: BatteryMetrics?) -> Self {
        guard let battery,
              battery.isPresent,
              !battery.isCharging,
              let chargeFraction = battery.chargeFraction else {
            return .normal
        }
        if chargeFraction <= 0.10 {
            return .critical
        }
        if chargeFraction <= 0.20 {
            return .warning
        }
        return .normal
    }
}
