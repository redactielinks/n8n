import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case httpError(Int)
    case decodingError(Error)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL:       return "Ongeldige server URL"
        case .networkError(let e): return "Netwerkfout: \(e.localizedDescription)"
        case .httpError(let c): return "HTTP fout \(c)"
        case .decodingError:    return "Kon reactie niet verwerken"
        case .unauthorized:     return "Ongeldige API-sleutel"
        }
    }
}

final class N8NAPIClient {

    private let server: N8NServer
    private let session: URLSession

    init(server: N8NServer) {
        self.server = server
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    // MARK: - Workflows

    func fetchWorkflows(completion: @escaping (Result<[Workflow], APIError>) -> Void) {
        guard let url = URL(string: "\(server.baseURL)/api/v1/workflows") else {
            completion(.failure(.invalidURL)); return
        }
        var request = URLRequest(url: url)
        request.setValue(server.apiKey, forHTTPHeaderField: "X-N8N-API-KEY")

        session.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(.networkError(error))); return }
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 401 { completion(.failure(.unauthorized)); return }
            guard (200..<300).contains(http.statusCode) else {
                completion(.failure(.httpError(http.statusCode))); return
            }
            guard let data = data else { completion(.failure(.httpError(0))); return }
            do {
                let decoded = try JSONDecoder().decode(WorkflowsResponse.self, from: data)
                completion(.success(decoded.data))
            } catch {
                completion(.failure(.decodingError(error)))
            }
        }.resume()
    }

    // MARK: - Trigger webhook

    func triggerWebhook(
        path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        completion: @escaping (Result<String, APIError>) -> Void
    ) {
        let urlString = "\(server.baseURL)/webhook/\(path)"
        guard let url = URL(string: urlString) else {
            completion(.failure(.invalidURL)); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        session.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(.networkError(error))); return }
            guard let http = response as? HTTPURLResponse else { return }
            guard (200..<300).contains(http.statusCode) else {
                completion(.failure(.httpError(http.statusCode))); return
            }
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? "OK"
            completion(.success(text))
        }.resume()
    }

    // MARK: - Health check

    func checkHealth(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(server.baseURL)/healthz") else {
            completion(false); return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        session.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse {
                completion((200..<300).contains(http.statusCode))
            } else {
                completion(false)
            }
        }.resume()
    }
}
