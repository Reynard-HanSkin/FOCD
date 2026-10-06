import Cocoa
import InputMethodKit

enum InputSourceManager {
    static var currentInputSource: Language {
        if Language.korean.inputSource!.isSelected {
            return .korean
        } else if Language.english.inputSource!.isSelected {
            return .english
        } else if Language.japanese.inputSource?.isSelected == true {
            return .japanese
        } else if Language.chinese.inputSource?.isSelected == true {
            return .chinese
        } else {
            logger.error("Failed to retrieve current input source.")
            return .english
        }
    }
    
    /// 입력기를 전환하고, 실제로 선택되었는지 검증하여 실패 시 재시도한다.
    ///
    /// 기존의 고정 딜레이 + 1회 재시도 방식과 달리, 전환 결과를 짧은 간격으로
    /// 확인하고 실패하면 지수 백오프로 재시도한다. 시스템 부하로 TIS 호출이
    /// 무시되는 상황에서도 마지막에 반드시 전환을 성공하도록 한다.
    static func setInputSource(to language: Language) {
        guard let target = language.inputSource else {
            logger.error("Attempted to set to unavailable input source.")
            return
        }

        Task.detached(priority: .userInitiated) {
            // Workaround for TISSelectInputSource KCJV issue:
            // 한글 등 IME 입력기는 영어 입력기를 경유하지 않으면 선택에 실패하는 경우가 있다.
            let english = Language.english.inputSource!

            await MainActor.run {
                if language != .english {
                    TISSelectInputSource(english)
                }
            }
            try? await Task.sleep(nanoseconds: 1_000_000) // 1ms

            await MainActor.run {
                if language != .english {
                    TISSelectInputSource(english)
                }
                TISSelectInputSource(target)
            }

            // 전환 검증 + 지수 백오프 재시도 (총 최대 ~1.3초)
            let retryDelays: [UInt64] = [10, 20, 40, 80, 160, 320, 640].map { $0 * 1_000_000 }
            for delay in retryDelays {
                try? await Task.sleep(nanoseconds: delay)

                let isSelected = await MainActor.run { target.isSelected }
                if isSelected { return }

                logger.info("입력기 전환 실패 감지, 재시도 (\(delay / 1_000_000)ms 경과)")
                await MainActor.run {
                    if language != .english {
                        TISSelectInputSource(english)
                    }
                    TISSelectInputSource(target)
                }
            }

            logger.error("입력기 전환 최종 실패: \(target.id)")
        }
    }
    
    /// 빠르게 다른 언어로 전환했다 돌아오기.
    ///
    /// 팝업 픽스 전용
    static func rapidDummyAction() {
        let current = currentInputSource
        if current == .english {
            TISSelectInputSource(Language.korean.inputSource!)
            TISSelectInputSource(Language.english.inputSource!)
        } else {
            TISSelectInputSource(Language.english.inputSource!)
            TISSelectInputSource(current.inputSource!)
        }
    }
    
    struct Language: Equatable {
        let inputSource: TISInputSource?
        
        /// A cache to avoid to repeating `String.contain(_:)`
        var isGuremTIS: Bool = false
        
        private init(_ inputSource: TISInputSource?) {
            self.inputSource = inputSource
        }
        
        private static let inputSources = {
            let inputSources = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
            return inputSources
        }()
        
        static let korean = {
            for source in inputSources {
                logger.debug("Available Kor-TIS ID: \(source.id)")
            }
            
            guard let inputSource = inputSources.first(where: {
                $0.id.hasPrefix("com.apple.inputmethod.Korean.")
                || $0.id.hasPrefix("org.youknowone.inputmethod.Gureum.")
            }) else {
                logger.error("Failed to find Korean input source from list.")
                fatalError("Failed to find Korean input source from list.")
            }
            var lang = Language(inputSource)
            
            if lang.inputSource!.id.hasPrefix("org.youknowone.inputmethod.Gureum.") {
                lang.isGuremTIS = true
            }
            
            return lang
        }()
        static let english = {
            guard let inputSource = inputSources.first(where: { $0.id == "com.apple.keylayout.ABC" }) else {
                logger.error("Failed to find English input source from list.")
                fatalError("Failed to find English input source from list.")
            }
            return Language(inputSource)
        }()
        static let japanese = {
            let inputSource = inputSources.first { $0.id == "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese" }
            if inputSource == nil {
                logger.info("No Japanese input source in list.")
            }
            return Language(inputSource)
        }()
        static let chinese = {
            let inputSource = inputSources.first { $0.id == "com.apple.inputmethod.SCIM.ITABC" }
            if inputSource == nil {
                logger.info("No Chinese input source in list.")
            }
            return Language(inputSource)
        }()
    }
}

extension TISInputSource {
    private func getProperty(_ key: CFString) -> AnyObject? {
        guard let cfType = TISGetInputSourceProperty(self, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(cfType).takeUnretainedValue()
    }
    
    static var current: TISInputSource {
        return TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
    }

    var id: String {
        return getProperty(kTISPropertyInputSourceID) as! String
    }

    var category: String {
        return getProperty(kTISPropertyInputSourceCategory) as! String
    }

    var isKeyboardInputSource: Bool {
        return category == (kTISCategoryKeyboardInputSource as String)
    }

    var isSelectable: Bool {
        return getProperty(kTISPropertyInputSourceIsSelectCapable) as! Bool
    }

    var isSelected: Bool {
        return getProperty(kTISPropertyInputSourceIsSelected) as! Bool
    }

    var sourceLanguages: [String] {
        return getProperty(kTISPropertyInputSourceLanguages) as! [String]
    }
}
