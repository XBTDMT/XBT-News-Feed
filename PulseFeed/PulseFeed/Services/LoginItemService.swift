import ServiceManagement

struct LoginItemService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                print("PulseFeed: [Login] Registered as login item")
            } else {
                try SMAppService.mainApp.unregister()
                print("PulseFeed: [Login] Unregistered from login items")
            }
        } catch {
            print("PulseFeed: [Login] Error: \(error)")
        }
    }
}
