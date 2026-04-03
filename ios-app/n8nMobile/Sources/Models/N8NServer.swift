import Foundation

struct N8NServer: Codable {
    var id: String
    var name: String
    var baseURL: String
    var apiKey: String

    init(id: String = UUID().uuidString, name: String, baseURL: String, apiKey: String) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
    }
}

struct Workflow: Codable {
    let id: String
    let name: String
    let active: Bool
    let createdAt: String?
    let updatedAt: String?
}

struct WorkflowsResponse: Codable {
    let data: [Workflow]
}

struct WebhookExecution: Codable {
    let webhookPath: String
    let httpMethod: String
}
