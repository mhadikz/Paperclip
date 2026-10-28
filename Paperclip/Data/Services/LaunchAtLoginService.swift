import Foundation
import ServiceManagement

/// Login item registration via `SMAppService` (macOS 13+). Fails outside /Applications or
/// for unsigned builds; callers surface the real status instead of assuming success.
@MainActor
final class LaunchAtLoginService: LaunchAtLoginServicing {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "Enabled"
        case .requiresApproval: return "Requires approval in System Settings › General › Login Items"
        case .notFound: return "Not registered"
        case .notRegistered: return "Not registered"
        @unknown default: return "Unknown"
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
