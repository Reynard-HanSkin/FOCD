import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var statusBar: NSStatusBar!
    var statusBarItem: NSStatusItem?
    let statusBarMenu: NSMenu = NSMenu()
    let inputManager = InputManager.shared
    let popupFix = PopupFix.shared
    
    @UserDefault(key: "com.GST.focd.pref.showStatusMenuItem")
    var showStatusMenuItem: Bool = true
    @UserDefault(key: "com.GST.focd.pref.fixPopup")
    var fixPopup: Bool = false
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Show hidden status bar icon on duplicated launching
        let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!)
        if runningApp.count > 1 {
            runningApp.first!.activate()
            app.terminate(self)
            return
        }
        
        statusBar = NSStatusBar.system

        let englishMenuItem = NSMenuItem()
        englishMenuItem.title = "English"
        englishMenuItem.target = self
        englishMenuItem.action = #selector(setInputSourceEnglish)
        englishMenuItem.identifier = NSUserInterfaceItemIdentifier("menuItem.english")
                
        let koreanMenuItem = NSMenuItem()
        koreanMenuItem.title = "한국어"
        koreanMenuItem.target = self
        koreanMenuItem.action = #selector(setInputSourceKorean)
        koreanMenuItem.identifier = NSUserInterfaceItemIdentifier("menuItem.korean")
        
        let japaneseMenuItem = NSMenuItem()
        japaneseMenuItem.title = "日本語"
        japaneseMenuItem.target = self
        japaneseMenuItem.action = #selector(setInputSourceJapanese)
        japaneseMenuItem.identifier = NSUserInterfaceItemIdentifier("menuItem.japanese")
        
        let chineseMenuItem = NSMenuItem()
        chineseMenuItem.title = "中文"
        chineseMenuItem.target = self
        chineseMenuItem.action = #selector(setInputSourceChinese)
        chineseMenuItem.identifier = NSUserInterfaceItemIdentifier("menuItem.chinese")
        
        let fixPopupMenuItem = NSMenuItem()
        fixPopupMenuItem.title = "한영 팝업 고치기 (베타)"
        fixPopupMenuItem.target = self
        fixPopupMenuItem.action = #selector(togglePopupFix)
        fixPopupMenuItem.identifier = NSUserInterfaceItemIdentifier("menuItem.fixPopup")
        
        let testItem = NSMenuItem()
        testItem.title = "시스템 설정 마법사 (베타)"
        testItem.target = self
        testItem.action = #selector(showDialog)
        testItem.identifier = NSUserInterfaceItemIdentifier("menuItem.preference")
        
        let hideBarItemMenuItem = NSMenuItem()
        hideBarItemMenuItem.title = "상태 바 아이콘 숨기기"
        hideBarItemMenuItem.target = self
        hideBarItemMenuItem.action = #selector(hideBarItem)
        
        let quitMenuItem = NSMenuItem()
        quitMenuItem.title = "종료"
        quitMenuItem.target = self
        quitMenuItem.action = #selector(quit)
        
        statusBarMenu.addItem(englishMenuItem)
        statusBarMenu.addItem(koreanMenuItem)
        statusBarMenu.addItem(japaneseMenuItem)
        statusBarMenu.addItem(chineseMenuItem)
        statusBarMenu.addItem(.separator())
        if #available(macOS 14, *) {
            statusBarMenu.addItem(fixPopupMenuItem)
        }
        statusBarMenu.addItem(testItem)
        statusBarMenu.addItem(hideBarItemMenuItem)
        statusBarMenu.addItem(.separator())
        statusBarMenu.addItem(quitMenuItem)
        
        if showStatusMenuItem {
            createBarItem()
        }
        
        inputManager.start()
        
        if #available(macOS 14, *), fixPopup {
            popupFix.start()
        }
        
        // Check HID access and request permission
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        if access.rawValue != 0 { // If NOT granted
            PreferenceHelper.askInputMonitoringPermission()
        }
    }
    
    func applicationWillBecomeActive(_ notification: Notification) {
        if !showStatusMenuItem {
            showStatusMenuItem = true
            createBarItem()
        }
    }
    
    func createBarItem() {
        statusBarItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusBarItem?.button {
            button.image = NSImage(systemSymbolName: "capslock.fill", accessibilityDescription: nil)
                        
            statusBarItem?.menu = statusBarMenu
        } else {
            logger.info("No status bar button.")
        }
    }
    
    func removeBarItem() {
        guard let statusBarItem else {
            logger.info("No status bar item.")
            return
        }
        
        statusBar.removeStatusItem(statusBarItem)
        self.statusBarItem = nil
    }
    
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.identifier?.rawValue {
        case "menuItem.english":
            if InputSourceManager.currentInputSource == .english {
                menuItem.state = .on
            } else {
                menuItem.state = .off
            }
        case "menuItem.korean":
            if InputSourceManager.currentInputSource == .korean {
                menuItem.state = .on
            } else {
                menuItem.state = .off
            }
        case "menuItem.japanese":
            if InputSourceManager.Language.japanese.inputSource == nil {
                menuItem.state = .off
                return false
            }
            if InputSourceManager.currentInputSource == .japanese {
                menuItem.state = .on
            } else {
                menuItem.state = .off
            }
        case "menuItem.chinese":
            if InputSourceManager.Language.chinese.inputSource == nil {
                menuItem.state = .off
                return false
            }
            if InputSourceManager.currentInputSource == .chinese {
                menuItem.state = .on
            } else {
                menuItem.state = .off
            }
        case "menuItem.fixPopup":
            menuItem.state = popupFix.isRunning ? .on : .off
        default: return true
        }
        
        return true
    }

    @objc func setInputSourceEnglish() {
        if InputSourceManager.currentInputSource != .english {
            InputSourceManager.setInputSource(to: .english)
        }
    }
    
    @objc func setInputSourceKorean() {
        if InputSourceManager.currentInputSource != .korean {
            InputSourceManager.setInputSource(to: .korean)
        }
    }
    
    @objc func setInputSourceJapanese() {
        if InputSourceManager.currentInputSource != .japanese {
            InputSourceManager.setInputSource(to: .japanese)
        }
    }
    
    @objc func setInputSourceChinese() {
        if InputSourceManager.currentInputSource != .chinese {
            InputSourceManager.setInputSource(to: .chinese)
        }
    }
    
    @objc func togglePopupFix() {
        if fixPopup {
            popupFix.stop()
            fixPopup = false
        } else {
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            
            if AXIsProcessTrustedWithOptions(options) {
                popupFix.start()
                fixPopup = true
            } else {
                let dialog = NSAlert()
                dialog.messageText = "접근성 권한 필요"
                dialog.informativeText = "해당 기능을 사용하기 위해선 접근성 권한이 필요합니다. '설정 > 개인정보 보호 및 보안 > 손쉬운 사용'에서 FOCD를 추가 후 재시작 해주세요."
                let button = dialog.addButton(withTitle: "설정")
                button.action = #selector(askAccessibilityPermission)
                dialog.runModal()
            }
        }
    }
    
    @objc
    func askAccessibilityPermission() {
        IOHIDRequestAccess(kIOHIDRequestTypePostEvent)
    }
    
    @objc func showDialog() {
        let dialog = PreferenceDialog()
        let hostController = NSHostingController(rootView: dialog)
        let window = NSWindow(contentViewController: hostController)
        let fixedWidth = 270
        let fixedHeight = 300
        window.setContentSize(.init(width: fixedWidth, height: fixedHeight))
        window.styleMask.remove(.resizable)
        window.styleMask.remove(.fullScreen)
        window.styleMask.remove(.miniaturizable)
        window.level = .modalPanel
        window.tabbingMode = .disallowed
        window.identifier = .init("pref-dialog")
        window.title = "시스템 설정 마법사"
        
        let controller = NSWindowController(window: window)
        controller.showWindow(self)
    }
    
    @objc func hideBarItem() {
        showStatusMenuItem = false
        removeBarItem()
    }
    
    @objc func quit() {
        app.terminate(self)
    }
}

