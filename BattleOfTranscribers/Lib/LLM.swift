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

func calendarAgent(_ history: [String], _ sentence: String, apiUrl: String, apiKey: String, modelName: String) async throws -> String {
    let startTime = CFAbsoluteTimeGetCurrent()
    let url = URL(string: "https://\(apiUrl)/chat/completions")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    let prompt = """
    You are an intelligent Family Calendar Assistant. You manage a Human Family's
    Calendar. When they tell you something about their calendar, you make the
    necessary updates in the Calendar, and respond in a way that conveys that
    you understood them, and that you have made the necessary changes. Repeat
    back what the Human said in different words to convey that you have understood
    and made the necessary changes.
    
    Current Human's name is Sanket. His family members are Aditi (wife),
    Aadi (elder son), and Rushi (younger son).
    
    Examples:
    ----
    Human: I have a Physical Therapy Apointment on Monday at 9 am.
    Assistant: Got it. Physical Therapy Apointment for Sanket on Monday at 9 am.
    ----
    Human: Remind Aditi to pick up milk from Store on her way back from Pilates tomorrow morning at 8 am.
    Assistant: Reminder set for Aditi for tomorrow at 8 am. Pick up milk from the Store on the way back from Pilates.
    ----
    """

    var messages: [Any] = []
    messages.append(["role": "system", "content": prompt])
    for (index, message) in history.enumerated() {
        messages.append(["role": index % 2 == 0 ? "user" : "system", "content": message])
    }
    messages.append(["role": "user", "content": sentence])
    
    let requestBody: [String: Any] = [
        "model": modelName,
        "messages": messages,
        "max_tokens": 500,
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
    
    let endTime = CFAbsoluteTimeGetCurrent()
    let duration = endTime - startTime
    let formattedDuration = String(format: "%.2f", duration * 1000)

    print("calendarAgent(\(formattedDuration)) : \(sentence)")

    return content
}
