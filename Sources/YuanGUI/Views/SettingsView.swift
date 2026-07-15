import SwiftUI

struct SettingsView: View {
    @ObservedObject var pet: PetStore
    @ObservedObject var ai: AISettingsStore
    @ObservedObject var loginItem: LoginItemStore
    @ObservedObject var focusTimer: FocusTimerStore
    let showPet: () -> Void
    @State private var selectedTab = 0
    @State private var promptEditorState: PromptEditorState?

    var body: some View {
        VStack(spacing: 0) {
            Picker("设置分类", selection: $selectedTab) {
                Label("桌宠", systemImage: "pawprint.fill").tag(0)
                Label("AI 对话", systemImage: "bubble.left.and.sparkles.fill").tag(1)
                Label("专注", systemImage: "timer").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(16)

            Divider()

            Group {
                if selectedTab == 0 {
                    ScrollView { petSettings.padding(.bottom, 8) }
                } else if selectedTab == 1 {
                    aiSettings
                } else {
                    focusSettings
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 540, height: 500)
        .background(.regularMaterial)
    }

    private var focusSettings: some View {
        Form {
            Section("陪伴式专注") {
                Stepper("专注时长：\(focusTimer.durationMinutes) 分钟", value: $focusTimer.durationMinutes, in: 1...180, step: 5)
                Text("专注期间桌宠保持安静，隐藏日常对白、天气播报和非紧急系统气泡；低电量与内存紧张仍会提醒。")
                    .font(.caption).foregroundStyle(.secondary)
                if focusTimer.state == .running || focusTimer.state == .paused {
                    Text(focusTimer.timeText).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                    HStack {
                        if focusTimer.state == .running {
                            Button("暂停") { focusTimer.pause() }
                        } else {
                            Button("继续") { focusTimer.resume() }
                        }
                        Button("提前结束") { focusTimer.stop() }
                    }
                } else {
                    Button("开始专注") { focusTimer.start(); showPet() }
                        .buttonStyle(.borderedProminent).tint(.orange)
                }
            }
        }
        .formStyle(.grouped)
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
                Toggle(pet.petMotionEnabled ? "帧动画已开启" : "帧动画已关闭", isOn: Binding(
                    get: { pet.petMotionEnabled },
                    set: pet.setPetMotionEnabled
                ))
                Text(pet.petMotionEnabled
                     ? "待机和自动对白会播放序列帧；动作切换时仍保留轻量位移、缩放与摆动。"
                     : "序列帧已关闭，空闲时使用静态动作轮播；动作切换的轻量动画仍会保留。低电量模式或“减少动态效果”开启时才会完全静止。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("桌宠主动和你说话", isOn: Binding(
                    get: { pet.ambientChatterEnabled },
                    set: pet.setAmbientChatterEnabled
                ))
                if pet.ambientChatterEnabled {
                    HStack {
                        Text("日常对白间隔")
                        Slider(
                            value: Binding(
                                get: { Double(pet.ambientChatterIntervalMinutes) },
                                set: { pet.setAmbientChatterIntervalMinutes(Int($0.rounded())) }
                            ),
                            in: 1...120,
                            step: 1
                        )
                        Text("\(pet.ambientChatterIntervalMinutes) 分钟")
                            .monospacedDigit()
                            .frame(width: 66, alignment: .trailing)
                    }
                    Toggle("天气刷新完成后主动播报", isOn: Binding(
                        get: { pet.weatherAnnouncementsEnabled },
                        set: pet.setWeatherAnnouncementsEnabled
                    ))
                }
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
                Button("恢复默认大小（75%）") { pet.setPetScale(PetLayout.defaultScale) }
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
                TextField("API 基础地址", text: Binding(
                    get: { ai.baseURL },
                    set: ai.updateBaseURL
                ))
                SecureField("API Key（保存在本机，仅当前用户可读）", text: Binding(
                    get: { ai.apiKey },
                    set: ai.updateAPIKey
                ))

                HStack {
                    if ai.isConnecting {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在读取模型…")
                            .foregroundStyle(.secondary)
                    } else if let message = ai.connectionMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(ai.availableModels.isEmpty ? .orange : .green)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("连接并读取模型") {
                        Task { await ai.connectAndLoadModels() }
                    }
                    .disabled(
                        ai.isConnecting
                            || ai.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || ai.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                if !ai.availableModels.isEmpty {
                    Picker("可用模型（\(ai.availableModels.count)）", selection: $ai.model) {
                        if !ai.model.isEmpty, !ai.availableModels.contains(ai.model) {
                            Text("手动：\(ai.model)").tag(ai.model)
                        }
                        ForEach(ai.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    TextField("手动模型名", text: $ai.model)
                } else {
                    TextField("模型（可手动填写）", text: $ai.model)
                }

                Button("查看或编辑角色提示词…") {
                    promptEditorState = PromptEditorState(prompt: ai.systemPrompt)
                }
            }
            .formStyle(.grouped)

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
        .sheet(item: $promptEditorState) { state in
            PromptEditorSheet(initialPrompt: state.prompt) { updatedPrompt in
                ai.systemPrompt = updatedPrompt
            }
        }
    }
}

private struct PromptEditorState: Identifiable {
    let id = UUID()
    let prompt: String
}

private struct PromptEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    let apply: (String) -> Void

    init(initialPrompt: String, apply: @escaping (String) -> Void) {
        _draft = State(initialValue: initialPrompt)
        self.apply = apply
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("角色提示词", systemImage: "text.quote")
                .font(.title3.bold())
            Text("修改会先应用到当前设置，点击主设置页的“保存”后才会持久保存。")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $draft)
                .font(.system(size: 12, design: .rounded))
                .padding(8)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator.opacity(0.5)))

            HStack {
                Button("恢复默认提示词") { draft = AISettingsStore.defaultPrompt }
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button("应用") {
                    apply(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 410)
        .background(.regularMaterial)
    }
}
