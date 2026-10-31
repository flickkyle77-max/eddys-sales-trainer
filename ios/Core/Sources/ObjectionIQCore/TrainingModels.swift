import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public var integer: Int? { if case .number(let n) = self, n.isFinite, n >= 0, n <= 100 { return Int(n) }; return nil }
}

public struct ConversationMessage: Codable, Equatable, Sendable {
    public let role: String
    public let text: String
    public init(role: String, text: String) { self.role = role; self.text = text }
}

public struct TranscriptTurn: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let speaker: String
    public var text: String
    public init(id: String, speaker: String, text: String) { self.id = id; self.speaker = speaker; self.text = text }
}

/// Reduces final transcript events by item ID. Duplicate provider events update a turn rather than adding speech twice.
public struct CallTranscript: Sendable {
    public private(set) var turns: [TranscriptTurn] = []
    public init() {}
    public mutating func receive(_ data: Data) throws {
        guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return }
        let speaker: String
        switch type {
        case "conversation.item.input_audio_transcription.completed": speaker = "Salesperson"
        case "response.output_audio_transcript.done": speaker = "Customer"
        default: return
        }
        guard let text = event["transcript"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let id = (event["item_id"] as? String) ?? (event["event_id"] as? String) ?? UUID().uuidString
        if let index = turns.firstIndex(where: { $0.id == id && $0.speaker == speaker }) { turns[index].text = text }
        else { turns.append(TranscriptTurn(id: id, speaker: speaker, text: text)) }
    }
    public var canScore: Bool { turns.count >= 2 && turns.contains { $0.speaker == "Salesperson" } }
}

public struct DrillState: Decodable, Sendable {
    public let id: String
    public let token: String
    public let topic: String
    public let customer: String
    public let messages: [ConversationMessage]
    public let turns: Int
    public let maxTurns: Int
}

public struct Coaching: Decodable, Sendable {
    public let assessment: String
    public let suggestion: String
    public let reason: String
    public let question: String?
}

public struct TrainingReview: Codable, Sendable {
    public struct Evidence: Codable, Sendable {
        public let quote: String
        public let evidence: String
        public let advice: String
    }
    public var total: Int?
    public var scores: [String: JSONValue]?
    public var outcome: String?
    public var strength: String?
    public var improvement: String?
    public var example: String?
    public var notes: String?
    public var real_concern: String?
    public var next_drill: String?
    public var mode: String?
    public var saved: Bool?
    public var saveToken: String?
    public var save_warning: String?
    public var feedback: [String: Evidence]?
    public init() {}
    public var dimensions: [(key: String, value: Int)] {
        (scores ?? [:]).compactMap { key, value in value.integer.map { (key, $0) } }.sorted { $0.key < $1.key }
    }
}

public struct SavedSession: Decodable, Identifiable, Sendable {
    public let recordID: String?
    public let created_at: String
    public let scenario: String
    public let difficulty: String
    public let language: String
    public let mode: String?
    public let total_score: Int
    public let scores: [String: JSONValue]?
    public let outcome: String?
    public let strength: String?
    public let improvement: String?
    public let example: String?
    public let conversation: [ConversationMessage]?
    public let opening: Int?
    public let rapport: Int?
    public let discovery: Int?
    public let objections: Int?
    public let appointment: Int?
    public let closing: Int?
    enum CodingKeys: String, CodingKey {
        case recordID = "id"
        case created_at, scenario, difficulty, language, mode, total_score, scores, outcome, strength, improvement, example, conversation
        case opening, rapport, discovery, objections, appointment, closing
    }
    public var id: String { recordID ?? "\(created_at)-\(scenario)-\(total_score)" }
    public var kind: String { scenario.hasPrefix("objection_") ? "Objection Lab" : scores == nil ? "Phone" : "Text" }
    public var review: TrainingReview {
        var review = TrainingReview()
        if let detail = scores?["_review"], let data = try? JSONEncoder().encode(detail),
           let saved = try? JSONDecoder().decode(TrainingReview.self, from: data) { review = saved }
        review.total = total_score
        review.outcome = outcome; review.strength = strength; review.improvement = improvement; review.example = example; review.mode = mode
        review.scores = scores ?? Dictionary(uniqueKeysWithValues: [
            ("opening", opening), ("rapport", rapport), ("discovery", discovery),
            ("objections", objections), ("appointment", appointment), ("closing", closing)
        ].compactMap { key, value in value.map { (key, JSONValue.number(Double($0))) } })
        return review
    }
}

public struct ObjectionCatalog: Decodable, Sendable {
    public struct Topic: Decodable, Sendable { public let label: String; public let goal: String }
    public let topics: [String: Topic]
    public let maxTurns: Int
}

public struct PracticeSettings: Equatable, Sendable {
    public var scenario = "internet"
    public var topic = "price"
    public var difficulty = "realistic"
    public var language = "en"
    public var mode = "practice"
    public var challenge = "focused"
    public init() {}
    public var body: [String: String] {
        ["scenario": scenario, "topic": topic, "difficulty": difficulty, "language": language, "mode": mode, "challenge": challenge]
    }
}
