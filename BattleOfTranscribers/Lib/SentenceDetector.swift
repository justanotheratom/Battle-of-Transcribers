import Foundation

struct GroqResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

func isCompleteSentence(_ sentence: String, apiUrl: String, apiKey: String, modelName: String) async throws -> Bool {
    let startTime = DispatchTime.now()
    let url = URL(string: "https://\(apiUrl)/chat/completions")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    let prompt = """
    Can the following fragment be the end of a sentence? It does not have to be a complete
    well-formed sentence, just the possible end of a sentence.
    Answer with just 'Yes' or 'No'.
    Fragment: "\(sentence)"
    """

    let requestBody: [String: Any] = [
        "model": modelName,
        "messages": [
            ["role": "user", "content": prompt]
        ],
        "max_tokens": 10,
        "temperature": 0
    ]

    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

    let (data, _) = try await URLSession.shared.data(for: request)
//    let jsonResponse = try! JSONSerialization.jsonObject(with: data, options: [])
//    print("isCompleteSentence: \(jsonResponse)")
    let response = try JSONDecoder().decode(GroqResponse.self, from: data)

    guard let content = response.choices.first?.message.content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else {
        throw NSError(domain: "ResponseError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to parse response"])
    }
    
    let endTime = DispatchTime.now()
    let nanoTime = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
    let timeInterval = Double(nanoTime) / 1_000_000 // Convert to milliseconds

    let result = content == "yes"

    print("isCompleteSentence(\(result), \(timeInterval) milliseconds) : \(sentence)")

    return result
}
