import SwiftUI

struct SettingsView: View {
    @ObservedObject var pet: PetStore
    @ObservedObject var ai: AISettingsStore
    let showPet: () -> Void
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("设置分类", selection: $selectedTab) {
                Label("桌宠", systemImage: "pawprint.fill").tag(0)
                Label("AI 对话", systemImage: "bubble.left.and.sparkles.fill").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(16)

            Divider()

            Group {
                if selectedTab == 0 { petSettings } else { aiSettings }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 520, height: 430)
        .background(.regularMaterial)
    }

    private var petSettings: some View {
        Form {
            Section("角色与外观") {
                Picker("当前角色", selection: Binding(
                    get: { pet.mode },
                    set: { pet.setMode($0); showPet() }
                )) {
                    ForEach(PetMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("桌宠大小")
                    Slider(
                        value: Binding(get: { pet.petScale }, set: pet.setPetScale),
                        in: PetLayout.minimumScale...PetLayout.maximumScale,
                        step: 0.05
                    )
                    Text("\(Int((pet.petScale * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }

                Picker("状态面板风格", selection: Binding(
                    get: { pet.dashboardStyle },
                    set: pet.setDashboardStyle
                )) {
                    ForEach(DashboardStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("行为") {
                Toggle("根据系统、天气和时间智能改变动作", isOn: Binding(
                    get: { pet.smartReactionsEnabled },
                    set: pet.setSmartReactionsEnabled
                ))
                Toggle("空闲时自动轮播普通动作（每分钟）", isOn: Binding(
                    get: { pet.idleAnimationEnabled },
                    set: pet.setIdleAnimationEnabled
                ))
                Toggle("在桌宠上方显示迷你状态气泡", isOn: Binding(
                    get: { pet.showsSystemStatus },
                    set: { value in if value != pet.showsSystemStatus { pet.toggleSystemStatus() } }
                ))
            }

            HStack {
                Button("恢复默认大小") { pet.setPetScale(1) }
                Spacer()
                Button("显示桌宠") { showPet() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
    }

    private var aiSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                TextField("API 基础地址", text: $ai.baseURL)
                TextField("模型", text: $ai.model)
                SecureField("API Key（保存在 macOS 钥匙串）", text: Binding(
                    get: { ai.apiKey },
                    set: ai.updateAPIKey
                ))
            }
            .formStyle(.grouped)

            Text("角色提示词")
                .font(.headline)
            TextEditor(text: $ai.systemPrompt)
                .font(.system(size: 11, design: .rounded))
                .padding(6)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator.opacity(0.5)))

            HStack {
                Button("恢复 MiMo 默认值") { ai.resetDefaults() }
                if let message = ai.saveMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("保存") { ai.save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
