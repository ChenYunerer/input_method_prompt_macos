import ServiceManagement

enum LoginItemStatus {
    case disabled, enabled, requiresApproval, unavailable

    var isRegistered: Bool { self == .enabled || self == .requiresApproval }
}

protocol LoginItemManaging {
    var status: LoginItemStatus { get }
    func setEnabled(_ enabled: Bool) throws
    func openSystemSettings()
}

final class LoginItemService: LoginItemManaging {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: return .disabled
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if !status.isRegistered { try SMAppService.mainApp.register() }
        } else if status.isRegistered {
            try SMAppService.mainApp.unregister()
        }
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
