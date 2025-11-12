import Foundation
import ServiceManagement

enum PreferenceHelper {
    static func setGlobalUserDefault(
        _ key: String,
        value: Any?
    ) throws(PreferenceError) {
        let defaults = UserDefaults.standard

        var domain = defaults.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]
        if let v = value {
            domain[key] = v
        } else {
            domain.removeValue(forKey: key)
        }
        
        defaults.setPersistentDomain(domain, forName: UserDefaults.globalDomain)
        
        // Flush
        let ok = CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        if !ok { throw .cfPrefSyncError }
    }
    
    static func disableCapslock(_ disable: Bool = true) throws(PreferenceError) {
        guard let keys = CFPreferencesCopyKeyList(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) as? [String] else {
            logger.error("[ModifierMapping] Failed to retreive key list from CF preferences")
            throw .cfPrefKeysNotFound
        }
        
        // Get mapping keys
        let mappingKeys = keys.filter { $0.hasPrefix("com.apple.keyboard.modifiermapping") }
        
        // Mapping values
        let defaultCapslockMapping = [
            "HIDKeyboardModifierMappingSrc" : 30064771129,
            "HIDKeyboardModifierMappingDst" : 30064771129
        ]
        let disabledCapslockMapping = [
            "HIDKeyboardModifierMappingSrc" : 30064771129,
            "HIDKeyboardModifierMappingDst" : 30064771072
        ]
        
        // Apply
        if !mappingKeys.isEmpty {
            // Modify all capslock key mapping -> diabled | default
            for key in mappingKeys {
                guard var mappings = CFPreferencesCopyValue(
                    key as CFString,
                    kCFPreferencesAnyApplication,
                    kCFPreferencesCurrentUser,
                    kCFPreferencesCurrentHost
                ) as? [[String: Int]] else {
                    logger.warning("[ModifierMapping] Failed to get value for key: \(key)")
                    continue
                }
                
                if let idx = mappings.firstIndex(where: { $0["HIDKeyboardModifierMappingSrc"] == 30064771129 }) {
                    mappings[idx] = disable ? disabledCapslockMapping : defaultCapslockMapping
                } else {
                    mappings.append(disable ? disabledCapslockMapping : defaultCapslockMapping)
                }
                
                let casted = mappings.map { $0 as NSDictionary } as NSArray
                CFPreferencesSetValue(
                    key as CFString,
                    casted,
                    kCFPreferencesAnyApplication,
                    kCFPreferencesCurrentUser,
                    kCFPreferencesCurrentHost
                )
            }
        } else if disable {
            logger.info("[ModifierMapping] Modifier mapping was empty. Setting global keyboard mapping...")
            let mapping = [disabledCapslockMapping]
            let casted = mapping.map { $0 as NSDictionary } as NSArray
            CFPreferencesSetValue(
                "com.apple.keyboard.modifiermapping.0-0-0" as CFString,
                casted,
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
        }
        
        // Flush
        let ok = CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        if !ok { throw .cfPrefSyncError }
    }
    
    static func registerLoginItem() throws {
        // Seems to be never failed
        try SMAppService.mainApp.register()
    }
    
    static func askInputMonitoringPermission() {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }
    
    static func askAccessibilityPermission() {
        IOHIDRequestAccess(kIOHIDRequestTypePostEvent)
    }
    
    // 재부팅은 유저가 수동으로 - 스크립트 권한 필요
}

enum PreferenceError: Error {
    case cfPrefKeysNotFound
    case cfPrefSyncError
}
