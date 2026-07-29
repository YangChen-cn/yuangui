import Foundation

enum PetChatterPeriod: String, CaseIterable, Sendable {
    case morning
    case afternoon
    case evening
    case lateNight

    static func resolve(at date: Date, calendar: Calendar = .current) -> Self {
        switch calendar.component(.hour, from: date) {
        case 5..<12: .morning
        case 12..<18: .afternoon
        case 18..<22: .evening
        default: .lateNight
        }
    }
}

struct PetChatterCandidate: Identifiable, Equatable, Sendable {
    let id: String
    let text: String
}

enum PetChatterSelector {
    static let historyLimit = 5

    static func eligible(
        from candidates: [PetChatterCandidate],
        recentIDs: [String]
    ) -> [PetChatterCandidate] {
        guard !candidates.isEmpty else { return [] }
        var excluded = Array(recentIDs.suffix(historyLimit))
        while true {
            let available = candidates.filter { !excluded.contains($0.id) }
            if !available.isEmpty { return available }
            guard !excluded.isEmpty else { return candidates }
            excluded.removeFirst()
        }
    }

    static func recording(_ id: String, in recentIDs: [String]) -> [String] {
        var updated = recentIDs.filter { $0 != id }
        updated.append(id)
        return Array(updated.suffix(historyLimit))
    }
}
