import Foundation

enum UpdateCheckReason {
    case automatic
    case manual
}

struct AutomaticUpdateCheckPolicy {
    static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    static func shouldCheck(
        for reason: UpdateCheckReason,
        isBundledApp: Bool,
        now: Date,
        lastSuccessfulAutomaticCheck: Date?
    ) -> Bool {
        switch reason {
        case .manual:
            return true
        case .automatic:
            break
        }
        guard isBundledApp else { return false }
        guard let lastSuccessfulAutomaticCheck else { return true }
        return now.timeIntervalSince(lastSuccessfulAutomaticCheck) >= automaticCheckInterval
    }
}

protocol AutomaticUpdateCheckDefaults: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: AutomaticUpdateCheckDefaults {}

struct AutomaticUpdateCheckState {
    static let lastSuccessfulCheckKey = "lastSuccessfulAutomaticUpdateCheck"

    private let defaults: any AutomaticUpdateCheckDefaults

    init(defaults: any AutomaticUpdateCheckDefaults = UserDefaults.standard) {
        self.defaults = defaults
    }

    var lastSuccessfulCheckDate: Date? {
        defaults.object(forKey: Self.lastSuccessfulCheckKey) as? Date
    }

    func recordSuccessfulCheck(_ reason: UpdateCheckReason, at date: Date) {
        switch reason {
        case .automatic:
            defaults.set(date, forKey: Self.lastSuccessfulCheckKey)
        case .manual:
            break
        }
    }
}
