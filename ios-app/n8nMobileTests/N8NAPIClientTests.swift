import XCTest
@testable import n8nMobile

final class N8NAPIClientTests: XCTestCase {

    func testServerModelEncoding() throws {
        let server = N8NServer(name: "Test", baseURL: "https://example.com", apiKey: "key-123")
        let data = try JSONEncoder().encode(server)
        let decoded = try JSONDecoder().decode(N8NServer.self, from: data)
        XCTAssertEqual(decoded.name, server.name)
        XCTAssertEqual(decoded.baseURL, server.baseURL)
        XCTAssertEqual(decoded.apiKey, server.apiKey)
    }

    func testWorkflowDecoding() throws {
        let json = """
        {
            "data": [
                {
                    "id": "abc123",
                    "name": "Mijn Workflow",
                    "active": true,
                    "createdAt": "2024-01-01T00:00:00.000Z",
                    "updatedAt": "2024-06-01T12:00:00.000Z"
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(WorkflowsResponse.self, from: data)
        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data[0].id, "abc123")
        XCTAssertEqual(response.data[0].name, "Mijn Workflow")
        XCTAssertTrue(response.data[0].active)
    }

    func testServerStorePersistence() {
        let store = ServerStore.shared
        // Clear state
        store.servers = []

        let server = N8NServer(name: "Local n8n", baseURL: "http://localhost:5678", apiKey: "test")
        store.add(server)
        XCTAssertEqual(store.servers.count, 1)
        XCTAssertEqual(store.servers[0].name, "Local n8n")

        store.delete(at: 0)
        XCTAssertEqual(store.servers.count, 0)
    }

    func testServerStoreUpdate() {
        let store = ServerStore.shared
        store.servers = []

        var server = N8NServer(name: "Oud", baseURL: "https://old.example.com", apiKey: "key")
        store.add(server)
        server.name = "Nieuw"
        store.update(server)

        XCTAssertEqual(store.servers[0].name, "Nieuw")
        store.servers = []
    }
}
