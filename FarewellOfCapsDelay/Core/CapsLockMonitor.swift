import Cocoa
import IOKit.hid

/// 캡스락 키 입력을 감지하고 시스템 기본 동작보다 먼저 가로채는 모니터.
///
/// 이중 구조로 동작한다.
/// - IOHIDManager(listen): 캡스락/Shift/Option의 다운·업을 판별하고 전환 로직을 트리거. (입력 모니터링 권한)
/// - CGEventTap(post): 캡스락 `flagsChanged` 이벤트를 소비하여 시스템이 캡스락 입력을
///   아예 인식하지 못하게 한다. 이로써 로마자 강제 전환과 "Caps Lock 켬/끔" HUD가
///   뜨지 않으며, 캡스락 상태를 앱이 완전히 소유한다. (접근성 권한)
final class CapsLockMonitor {
    static let shared = CapsLockMonitor()

    private(set) var isCapslockOn = false
    private(set) var lastCapslockPressedTime = Date()

    /// CGEventTap 설치 성공 여부. 접근성 권한이 없으면 `false`.
    private(set) var isEventTapEnabled = false

    private var hidManager: IOHIDManager?
    private var eventTap: CFMachPort?
    /// 캡스락 LED 제어용 HID 시스템 연결. 앱 생애주기 동안 한 번만 열어 재사용한다.
    private var hidConnect: io_connect_t = 0

    private var isShiftPressed = false
    private var isOptionPressed = false
    private var tertiaryIM: InputSourceManager.Language?

    private init() {
        _ = InputSourceManager.currentInputSource // Initialize static variable
        if InputSourceManager.Language.japanese.inputSource != nil {
            tertiaryIM = .japanese
        } else if InputSourceManager.Language.chinese.inputSource != nil {
            tertiaryIM = .chinese
        } else {
            tertiaryIM = nil
        }
    }

    func start() {
        openHIDParamConnect()
        startHIDListener()
        installEventTap()
    }

    /// 권한 승인 후 등 탭 설치가 필요할 때 재시도한다.
    func installEventTapIfNeeded() {
        guard eventTap == nil else { return }
        installEventTap()
    }

    // MARK: - HID Listener (키 감지)

    private func startHIDListener() {
        let hid = IOHIDManagerCreate(kCFAllocatorDefault, 0)

        let deviceFilter = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard
        ] as CFDictionary
        IOHIDManagerSetDeviceMatching(hid, deviceFilter)

        var inputValueFilter = [
            Keys.capsLock,
            Keys.lShift,
            Keys.rShift,
        ]

        if tertiaryIM != nil {
            inputValueFilter.append(contentsOf: [
                Keys.lOption,
                Keys.rOption
            ])
        }

        let filter = inputValueFilter.map {
            [kIOHIDElementUsageKey: $0] as CFDictionary
        } as CFArray
        IOHIDManagerSetInputValueMatchingMultiple(hid, filter)

        let callback: IOHIDValueCallback = { context, result, sender, value in
            guard result == kIOReturnSuccess else { return }
            guard let context = context else { return }
            let unmanagedSelf = Unmanaged<CapsLockMonitor>.fromOpaque(context).takeUnretainedValue()

            unmanagedSelf.checkInput(value)
        }
        IOHIDManagerRegisterInputValueCallback(hid, callback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let res = IOHIDManagerOpen(hid, 0)
        if res != kIOReturnSuccess {
            logger.fault("Failed to initialize hid (입력 모니터링 권한 확인 필요)")
            IOHIDManagerClose(hid, 0)
            return
        }

        self.hidManager = hid
    }

    private func checkInput(_ value: IOHIDValue) {
        let usage = IOHIDElementGetUsage(IOHIDValueGetElement(value))
        let keyState = IOHIDValueGetIntegerValue(value) != 0 ? KeyState.keyDown : KeyState.keyUp

        switch (usage, keyState) {
        case (Keys.capsLock, .keyDown):
            lastCapslockPressedTime = .now

            if isShiftPressed {
                // 캡스락 토글 + 영어 입력기
                isCapslockOn.toggle()
                setCapslockState(isCapslockOn)
                if InputSourceManager.currentInputSource != .english {
                    InputSourceManager.setInputSource(to: .english)
                }
                return
            } else if isCapslockOn {
                // 캡스락 해제만 수행
                isCapslockOn = false
                setCapslockState(false)
                return
            }

            if tertiaryIM != nil && isOptionPressed {
                if InputSourceManager.currentInputSource != tertiaryIM! {
                    InputSourceManager.setInputSource(to: tertiaryIM!)
                } else {
                    InputSourceManager.setInputSource(to: .english)
                }
                return
            }

            if InputSourceManager.currentInputSource != .english {
                InputSourceManager.setInputSource(to: .english)
            } else {
                InputSourceManager.setInputSource(to: .korean)
            }

        case (Keys.lShift, .keyDown): fallthrough
        case (Keys.rShift, .keyDown):
            isShiftPressed = true
        case (Keys.lShift, .keyUp): fallthrough
        case (Keys.rShift, .keyUp):
            isShiftPressed = false
        case (Keys.lOption, .keyDown): fallthrough
        case (Keys.rOption, .keyDown):
            isOptionPressed = true
        case (Keys.lOption, .keyUp): fallthrough
        case (Keys.rOption, .keyUp):
            isOptionPressed = false

        default: return
        }
    }

    // MARK: - CGEventTap (시스템 이벤트 소비)

    private func installEventTap() {
        // flagsChanged 이벤트만 관심 대상. 캡스락(keycode 57) 이벤트는 소비하여
        // 시스템 기본 동작(로마자 전환, 캡스락 HUD, 시스템 캡스락 상태 변경)을 차단한다.
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: capsLockEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.fault("Failed to create event tap (접근성 권한 확인 필요)")
            isEventTapEnabled = false
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        isEventTapEnabled = true
    }

    fileprivate func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> CGEvent? {
        // 시스템이 탭을 일시 중단한 경우 재활성화
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return event
        }

        guard type == .flagsChanged else { return event }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        if keycode == Keys.capsLockKeycode {
            // 소비: 시스템에 캡스락 입력으로 인식되지 않음
            return nil
        }

        return event
    }

    // MARK: - Capslock LED State

    private func openHIDParamConnect() {
        let ioService = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard ioService != 0 else {
            logger.fault("Failed to find HID system service")
            return
        }

        let result = IOServiceOpen(ioService, mach_task_self_, UInt32(kIOHIDParamConnectType), &hidConnect)
        IOObjectRelease(ioService)

        if result != KERN_SUCCESS {
            logger.fault("Failed to open HID param connect: \(result)")
            hidConnect = 0
        }
    }

    private func setCapslockState(_ state: Bool) {
        guard hidConnect != 0 else { return }
        IOHIDSetModifierLockState(hidConnect, Int32(kIOHIDCapsLockState), state)
    }

    private struct Keys {
        static let capsLock: UInt32 = 0x39
        static let capsLockKeycode: Int64 = 57 // kVK_CapsLock
        static let lShift: UInt32 = 0xE1
        static let rShift: UInt32 = 0xE5
        static let lOption: UInt32 = 0xE2
        static let rOption: UInt32 = 0xE6
    }

    private enum KeyState {
        case keyDown, keyUp
    }
}

/// CGEventTap의 C 함수 컨벤션 콜백. 이벤트 소유권은 호출자에게 있으므로 unretained로 반환한다.
private func capsLockEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<CapsLockMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if monitor.handleEvent(proxy: proxy, type: type, event: event) == nil {
        return nil // 이벤트 소비
    }
    return Unmanaged.passUnretained(event)
}
