import Foundation

struct PetSmartStateEvaluation: Equatable {
    let states: [SmartPetState]
    let batteryAlertLevel: BatteryAlertLevel
}
