import Foundation

final class ServerStore {

    static let shared = ServerStore()
    private let key = "n8n_saved_servers"

    private init() {}

    var servers: [N8NServer] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([N8NServer].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }

    func add(_ server: N8NServer) {
        var list = servers
        list.append(server)
        servers = list
    }

    func update(_ server: N8NServer) {
        var list = servers
        if let idx = list.firstIndex(where: { $0.id == server.id }) {
            list[idx] = server
        }
        servers = list
    }

    func delete(at index: Int) {
        var list = servers
        list.remove(at: index)
        servers = list
    }
}
