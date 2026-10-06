import SwiftUI

struct PreferenceDialog: View {
    @State private var options: Set<Option> = [.disableCapslockIMSwitch]
    @State private var failed: Set<Option> = []
    @State private var done = false
    @State private var showDoneAlert: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                ForEach(Option.allCases) {
                    optionCheckBox($0)
                }
            }
            
            Divider()
                .padding(.vertical, 10)
            
            HStack {
                Button("취소", role: .cancel, action: dismissWindow)
                    .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("적용", action: apply)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 10)
            .alert("적용 완료", isPresented: $showDoneAlert) {
                
            } message: {
                if failed.isEmpty {
                    Text("성공적으로 설정을 적용하였습니다. 수동으로 컴퓨터를 재시동 해주세요.")
                } else {
                    Text("일부 설정이 실패하였습니다. 수동으로 설정 후 컴퓨터를 재시동 해주세요.")
                }
            }
        }
        .padding()
    }
    
    private func binding(_ option: Option) -> Binding<Bool> {
        Binding {
            options.contains(option)
        } set: {
            if $0 {
                options.insert(option)
            } else {
                options.remove(option)
            }
        }
    }
    
    @ViewBuilder
    private func optionCheckBox(_ option: Option) -> some View {
        var successColor: Color {
            failed.contains(option) ? .red : .green
        }
        Toggle(option.label, isOn: binding(option))
            .foregroundStyle((done && options.contains(option)) ? successColor : .primary)
        Text(option.description)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    
    private func apply() {
        failed = Set(options.sorted { $0.rawValue < $1.rawValue }
            .filter { !$0.apply() })
        done = true
        showDoneAlert = true
        
        if failed.isEmpty {
            playSound(success: true)
        } else {
            playSound(success: false)
        }
    }
    
    private func playSound(success: Bool) {
        if success {
            NSSound(named: "Blow")?.play()
        } else {
            NSSound(named: "Ping")?.play()
        }
    }
    
    private func dismissWindow() {
        app.windows.first { $0.identifier == .init("pref-dialog") }?.close()
    }
}

fileprivate enum Option: Int, CaseIterable, Identifiable {
    case disableCapslockIMSwitch
    case disableCapslockFuction
    case registerLaunchAgent
    
    var id: Int { rawValue }
    
    var label: String {
        switch self {
        case .disableCapslockIMSwitch: "캡스락 한영전환 비활성화"
        case .disableCapslockFuction: "캡스락 기능 비활성화"
        case .registerLaunchAgent: "로그인 항목에 추가"
        }
    }
    
    var description: String {
        switch self {
        case .disableCapslockIMSwitch: "macOS 기본 캡스락 한영전환을 비활성화 (필수)"
        case .disableCapslockFuction: "캡스락 인디케이터가 깜빡이는 것을 방지 (선택)"
        case .registerLaunchAgent: "부팅시 자동으로 실행 (선택)"
        }
    }
    
    /// Returns `true` if success
    func apply() -> Bool {
        do {
            switch self {
            case .disableCapslockIMSwitch:
                try PreferenceHelper.setGlobalUserDefault("TISRomanSwitchState", value: 0)
            case .disableCapslockFuction:
                try PreferenceHelper.disableCapslock()
            case .registerLaunchAgent:
                try PreferenceHelper.registerLoginItem()
            }
        } catch {
            logger.error("Preference error: \(error)")
            return false
        }
        
        return true
    }
}
