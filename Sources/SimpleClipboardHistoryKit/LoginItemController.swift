import ServiceManagement

/// Injectable boundary: reading status never registers the application.
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSettings()
}

struct MainAppLoginItemService: LoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

final class LoginItemController {
    private let service: LoginItemService
    private(set) var errorMessage: String?
    init(service: LoginItemService = MainAppLoginItemService()) { self.service = service }
    var status: SMAppService.Status { service.status }
    var isEnabled: Bool { status == .enabled }
    var message: String? {
        if let errorMessage { return "Login item: \(errorMessage)" }
        switch status {
        case .requiresApproval: return "Login item needs approval in System Settings"
        case .notFound: return "Login item unavailable; use an installed, signed app"
        default: return nil
        }
    }
    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                if status == .requiresApproval { service.openSettings() }
                else if status != .enabled { try service.register() }
            } else if status != .notRegistered { try service.unregister() }
        } catch { errorMessage = error.localizedDescription }
    }
    func openSettings() { service.openSettings() }
}
