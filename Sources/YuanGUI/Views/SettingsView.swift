import SwiftUI

struct SettingsView: View {
    @ObservedObject var pet: PetStore
    @ObservedObject var ai: AISettingsStore
    @ObservedObject var loginItem: LoginItemStore
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
                if selectedTab == 0 {
                    ScrollView { petSettings.padding(.bottom, 8) }
                } else {
                    aiSettings
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 540, height: 500)
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
                Toggle("登录时自动启动", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: loginItem.setEnabled
                ))
                if loginItem.status == .requiresApproval {
                    HStack {
                        Text("需要在系统设置中批准登录项").font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button("打开系统设置") { loginItem.openSystemSettings() }
                    }
                } else if let message = loginItem.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                if !loginItem.isInApplicationsFolder {
                    Text("建议先把 YuanGUI.app 放入“应用程序”文件夹，再开启自启，避免重新构建后路径失效。")
                        .font(.caption).foregroundStyle(.orange)
                }
                Toggle("根据系统、天气和时间智能改变动作", isOn: Binding(
                    get: { pet.smartReactionsEnabled },
                    set: pet.setSmartReactionsEnabled
                ))
                Toggle("夜深了提醒", isOn: Binding(
                    get: { pet.bedtimeReminderEnabled },
                    set: pet.setBedtimeReminderEnabled
                ))
                if pet.bedtimeReminderEnabled {
                    HStack {
                        Text("提醒时段")
                        Spacer()
                        Picker("开始", selection: Binding(
                            get: { pet.bedtimeStartMinutes },
                            set: pet.setBedtimeStartMinutes
                        )) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(String(format: "%02d:00", hour)).tag(hour * 60)
                            }
                        }
                        .labelsHidden().frame(width: 92)
                        Text("至")
                        Picker("结束", selection: Binding(
                            get: { pet.bedtimeEndMinutes },
                            set: pet.setBedtimeEndMinutes
                        )) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(String(format: "%02d:00", hour)).tag(hour * 60)
                            }
                        }
                        .labelsHidden().frame(width: 92)
                    }
                    Text("支持跨午夜时段；默认 23:00–05:00。关闭后不再出现睡觉动作和提醒气泡。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("空闲时自动轮播普通动作（每分钟）", isOn: Binding(
                    get: { pet.idleAnimationEnabled },
                    set: pet.setIdleAnimationEnabled
                ))
                Toggle("在桌宠上方显示迷你状态气泡", isOn: Binding(
                    get: { pet.showsSystemStatus },
                    set: pet.setSystemStatusVisible
                ))
                Toggle("锁定桌宠并允许鼠标点击穿透", isOn: Binding(
                    get: { pet.interactionLocked },
                    set: pet.setInteractionLocked
                ))
            }

            HStack {
                Button("恢复默认大小（85%）") { pet.setPetScale(PetLayout.defaultScale) }
                Spacer()
                Button("显示桌宠") { showPet() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refresh() }
    }

    private var aiSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                TextField("API 基础地址", text: $ai.baseURL)
                TextField("模型", text: $ai.model)
                SecureField("API Key（保存在本机，仅当前用户可读）", text: Binding(
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
