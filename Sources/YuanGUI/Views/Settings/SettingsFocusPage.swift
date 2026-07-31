import SwiftUI

struct SettingsFocusPage: View {
    @ObservedObject var focusTimer: FocusTimerStore
    let showPet: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.pageSpacing) {
            SettingsPageHeader(
                title: "专注",
                subtitle: "用番茄钟保持节奏，专注期间让桌宠安静陪伴",
                systemImage: "timer",
                accent: .orange
            )
            Form {
                Section("陪伴式专注") {
                    Stepper(
                        AppLocalizer.format("focus.duration", focusTimer.durationMinutes),
                        value: Binding(
                            get: { focusTimer.durationMinutes },
                            set: focusTimer.setDurationMinutes
                        ),
                        in: FocusTimerStore.minimumDurationMinutes...FocusTimerStore.maximumDurationMinutes,
                        step: 5
                    )
                    Text("专注期间桌宠保持安静，隐藏日常对白、天气播报和非紧急系统气泡；低电量与内存紧张仍会提醒。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if focusTimer.state == .running || focusTimer.state == .paused {
                        Text(focusTimer.timeText)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        HStack {
                            if focusTimer.state == .running {
                                Button("暂停", action: focusTimer.pause)
                            } else {
                                Button("继续", action: focusTimer.resume)
                            }
                            Button("提前结束", action: focusTimer.stop)
                        }
                    } else {
                        Button("开始专注") {
                            focusTimer.start()
                            showPet()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}
