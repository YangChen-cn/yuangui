import Combine
import Foundation

@MainActor
final class AISettingsStore: ObservableObject {
    static let defaultBaseURL = "https://api.xiaomimimo.com/v1"
    static let defaultModel = "mimo-v2.5"
    static let defaultPrompt = """
    你是住在 macOS 桌面上的元圭和蓝猫 VCC。你们是亲密、可爱又聪明的桌宠搭档。
    回复时使用自然简短的中文，语气温柔俏皮：元圭会体贴地关心用户，VCC 偶尔用“喵”、小猫动作或吐槽补充，但不要每句话都卖萌。
    当用户需要严肃、准确的帮助时，先把事情说清楚，再保留一点元圭与 VCC 的可爱风格。不要声称做了实际未完成的操作，也不要编造系统状态。
    默认将用户称为“你”。除非用户要求，单次回复尽量控制在 200 字内。
    """

    @Published var baseURL: String
    @Published var model: String
    @Published var systemPrompt: String
    @Published private(set) var apiKey: String
    @Published private(set) var saveMessage: String?
    @Published private(set) var availableModels: [String] = []
    @Published private(set) var isConnecting = false
    @Published private(set) var connectionMessage: String?

    private let defaults: UserDefaults
    private let secrets: SecretStoring
    private let modelService: AIModelListing
    private let keychainService = "com.yang.yuangui.mimo-api-key"
    private let keychainAccount = "default"

    init(
        defaults: UserDefaults = .standard,
        secrets: SecretStoring = LocalSecretStore(),
        modelService: AIModelListing = AIModelService()
    ) {
        self.defaults = defaults
        self.secrets = secrets
        self.modelService = modelService
        baseURL = defaults.string(forKey: "aiBaseURL") ?? Self.defaultBaseURL
        let savedModel = defaults.string(forKey: "aiModel")
        model = savedModel == "mimo-v2.5-pro" ? Self.defaultModel : (savedModel ?? Self.defaultModel)
        if savedModel == "mimo-v2.5-pro" { defaults.set(Self.defaultModel, forKey: "aiModel") }
        systemPrompt = defaults.string(forKey: "aiSystemPrompt") ?? Self.defaultPrompt
        apiKey = secrets.read(service: keychainService, account: keychainAccount) ?? ""
    }

    func updateAPIKey(_ value: String) {
        apiKey = value
        connectionMessage = nil
        availableModels = []
    }

    func updateBaseURL(_ value: String) {
        baseURL = value
        connectionMessage = nil
        availableModels = []
    }

    func connectAndLoadModels() async {
        guard !isConnecting else { return }
        isConnecting = true
        connectionMessage = nil
        defer { isConnecting = false }
        do {
            let models = try await modelService.models(baseURL: baseURL, apiKey: apiKey)
            availableModels = models
            let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedModel.isEmpty { model = models[0] }
            connectionMessage = "连接成功，读取到 \(models.count) 个模型"
        } catch {
            availableModels = []
            connectionMessage = error.localizedDescription
        }
    }

    func save() {
        baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        systemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(baseURL, forKey: "aiBaseURL")
        defaults.set(model, forKey: "aiModel")
        defaults.set(systemPrompt, forKey: "aiSystemPrompt")
        do {
            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try secrets.delete(service: keychainService, account: keychainAccount)
            } else {
                try secrets.save(apiKey, service: keychainService, account: keychainAccount)
            }
            saveMessage = "已保存到本机应用数据（仅当前用户可读）"
        } catch {
            saveMessage = "本地保存失败，本次运行仍可使用：\(error.localizedDescription)"
        }
    }

    func resetDefaults() {
        baseURL = Self.defaultBaseURL
        model = Self.defaultModel
        systemPrompt = Self.defaultPrompt
        saveMessage = nil
        connectionMessage = nil
        availableModels = []
    }
}
