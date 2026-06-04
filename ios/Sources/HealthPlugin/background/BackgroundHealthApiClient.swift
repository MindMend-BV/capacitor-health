import Foundation

final class BackgroundHealthApiClient {
    private let session: URLSession
    private let connectTimeout: TimeInterval = 30
    private let readTimeout: TimeInterval = 30

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLastSyncMap(
        config: BackgroundSyncApiRequestConfig,
        subjectId: String,
        completion: @escaping (Result<[String: String], Error>) -> Void
    ) {
        let urlString = urlWithSubjectPath(baseUrl: config.url, subjectId: subjectId)
        guard let url = URL(string: urlString) else {
            completion(.failure(BackgroundHealthApiError.invalidUrl))
            return
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: connectTimeout)
        request.httpMethod = "GET"
        applyHeaders(config.headers, to: &request)

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(BackgroundHealthApiError.invalidResponse))
                return
            }
            guard (200 ... 299).contains(http.statusCode) else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                completion(.failure(BackgroundHealthApiError.httpStatus(http.statusCode, body)))
                return
            }
            guard let data = data else {
                completion(.failure(BackgroundHealthApiError.emptyBody))
                return
            }
            do {
                completion(.success(try self.parseLastSyncMap(from: data)))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    func uploadSamples(
        config: BackgroundSyncApiRequestConfig,
        subjectId: String,
        samples: [[String: Any]],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let url = URL(string: config.url) else {
            completion(.failure(BackgroundHealthApiError.invalidUrl))
            return
        }

        let body: [String: Any] = [
            "data": [
                "healthSubjectId": subjectId,
                "sourcePlatform": "APPLE_HEALTH",
                "deliveredViaBackgroundSync": true,
                "samples": samples
            ] as [String: Any]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(BackgroundHealthApiError.encodingFailed))
            return
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: readTimeout)
        request.httpMethod = "POST"
        request.httpBody = httpBody
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyHeaders(config.headers, to: &request)

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(BackgroundHealthApiError.invalidResponse))
                return
            }
            guard (200 ... 299).contains(http.statusCode) else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                completion(.failure(BackgroundHealthApiError.httpStatus(http.statusCode, body)))
                return
            }
            completion(.success(()))
        }
        task.resume()
    }

    private func parseLastSyncMap(from data: Data) throws -> [String: String] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObject = json["data"] as? [String: Any],
              let items = dataObject["items"] as? [[String: Any]] else {
            throw BackgroundHealthApiError.invalidPayload("Missing data.items in last sync response.")
        }

        var map: [String: String] = [:]
        for row in items {
            guard let dataType = row["dataType"] as? String, !dataType.isEmpty else { continue }
            guard HealthDataType(rawValue: dataType) != nil else {
                NSLog("[BackgroundHealthApi] Skipping unknown last-sync key: \(dataType)")
                continue
            }
            guard let lastSyncAt = row["lastSyncAt"] as? String, !lastSyncAt.isEmpty else {
                throw BackgroundHealthApiError.invalidPayload("Missing lastSyncAt for health data type: \(dataType)")
            }
            map[dataType] = lastSyncAt
        }
        return map
    }

    private func urlWithSubjectPath(baseUrl: String, subjectId: String) -> String {
        let trimmed = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encoded = subjectId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? subjectId
        return "\(trimmed)/\(encoded)"
    }

    private func applyHeaders(_ headers: [String: String], to request: inout URLRequest) {
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }
}

enum BackgroundHealthApiError: LocalizedError {
    case invalidUrl
    case invalidResponse
    case emptyBody
    case encodingFailed
    case httpStatus(Int, String)
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case .invalidUrl:
            return "Background sync API URL is invalid."
        case .invalidResponse:
            return "Background sync API response was invalid."
        case .emptyBody:
            return "Background sync API response body was empty."
        case .encodingFailed:
            return "Failed to encode background sync upload body."
        case let .httpStatus(code, body):
            if body.isEmpty {
                return "Background sync API request failed with status \(code)."
            }
            return "Background sync API request failed with status \(code). Response: \(body)"
        case let .invalidPayload(message):
            return message
        }
    }
}
