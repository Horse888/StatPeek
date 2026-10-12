import ServiceManagement

enum LoginItemStatus {
    case notRegistered, enabled, requiresApproval, notFound
}

@MainActor
protocol LoginItemService {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

@MainActor
private struct MainAppLoginItemService: LoginItemService {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .notFound
        }
    }

    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

@MainActor
final class LoginItemController {
    private let service: any LoginItemService
    private(set) var errorMessage: String?
    var status: LoginItemStatus { service.status }

    init(service: (any LoginItemService)? = nil) {
        self.service = service ?? MainAppLoginItemService()
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                if status == .notRegistered || status == .notFound { try service.register() }
            } else if status == .enabled || status == .requiresApproval {
                try service.unregister()
            }
        } catch {
            errorMessage = "设置失败：\(error.localizedDescription)"
        }
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
