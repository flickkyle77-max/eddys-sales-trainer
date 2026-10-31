import Foundation
import ObjectionIQCore

var count = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    count += 1
    guard condition() else { fatalError("Policy check failed: \(message)") }
}
func rejects(_ value: String) {
    count += 1
    do {
        _ = try ServerOrigin(value)
        fatalError("Unsafe server configuration was accepted: \(value)")
    } catch ServerOrigin.ConfigurationError.invalidServerURL {
        // Expected: invalid configurations must fail before a web view is loaded.
    } catch {
        fatalError("Unexpected validation failure: \(error)")
    }
}

let origin = try ServerOrigin("  https://TRAINING.example.test  ")
check(origin.url.absoluteString == "https://training.example.test/", "normalized HTTPS root")
check(origin.port == 443, "default HTTPS port")
for value in ["", "training.example.test", "http://training.example.test", "file:///index.html",
              "https://user:password@training.example.test", "https://training.example.test/app",
              "https://training.example.test:0", "https://training.example.test?redirect=other", "https://training.example.test/#anything"] {
    rejects(value)
}
check(origin.contains(URL(string: "https://training.example.test/api/session")), "same-origin API path")
check(origin.contains(URL(string: "https://TRAINING.example.test:443/?mode=phone")), "explicit HTTPS port")
for value in ["http://training.example.test/", "https://training.example.test.attacker.test/",
              "https://other.example.test/", "https://training.example.test:444/",
              "https://user@training.example.test/", "https://training.example.test:0/"] {
    check(!origin.contains(URL(string: value)), "reject untrusted navigation: \(value)")
}
check(!origin.contains(nil), "reject missing URL")
check(origin.matches(scheme: "https", host: "training.example.test", port: 0), "WebKit default port")
let custom = try ServerOrigin("https://training.example.test:8443")
check(custom.matches(scheme: "https", host: "training.example.test", port: 8443), "explicit configured port")
check(!custom.matches(scheme: "https", host: "training.example.test", port: 0), "no custom-port downgrade")

func mayCapture(host: String = "training.example.test", frame: String = "training.example.test",
                main: Bool = true, device: ServerOrigin.CaptureDevice = .microphone,
                current: String = "https://training.example.test/") -> Bool {
    origin.permitsMicrophoneRequest(
        scheme: "https", host: host, port: 443,
        frameScheme: "https", frameHost: frame, framePort: 443,
        isMainFrame: main, device: device, currentURL: URL(string: current))
}
check(mayCapture(), "trusted microphone request reaches iOS consent")
check(!mayCapture(host: "untrusted.example.test"), "untrusted requester denied")
check(!mayCapture(frame: "untrusted.example.test"), "untrusted frame denied")
check(!mayCapture(main: false), "embedded frame denied")
check(!mayCapture(device: .camera), "camera denied")
check(!mayCapture(device: .cameraAndMicrophone), "combined capture denied")
check(!mayCapture(device: .unknown), "unknown device denied")
check(!mayCapture(current: "https://untrusted.example.test/"), "navigation away revokes capture eligibility")
var transcript = CallTranscript()
func event(_ type: String, _ id: String, _ text: String) -> Data {
    try! JSONSerialization.data(withJSONObject: ["type": type, "item_id": id, "transcript": text])
}
try transcript.receive(event("conversation.item.input_audio_transcription.completed", "user1", "What matters most?"))
check(!transcript.canScore, "one turn cannot be graded")
try transcript.receive(event("response.output_audio_transcript.done", "customer1", "The total price."))
check(transcript.canScore, "customer and salesperson turns enable grading")
try transcript.receive(event("response.output_audio_transcript.done", "customer1", "The total price including fees."))
check(transcript.turns.count == 2, "duplicate transcript events cannot inflate the call")
check(transcript.turns.last?.text == "The total price including fees.", "final transcript updates existing turn")
try transcript.receive(event("response.output_audio_transcript.delta", "partial", "Partial"))
try transcript.receive(event("conversation.item.input_audio_transcription.completed", "blank", "  "))
check(transcript.turns.count == 2, "partial and blank transcript events are excluded")
let phoneFixture = Data("""
{"created_at":"2026-10-31T15:00:00Z","scenario":"internet","difficulty":"realistic","language":"en","total_score":70,"opening":10,"rapport":10,"discovery":15,"objections":15,"appointment":10,"closing":10,"outcome":"Follow-up agreed."}
""".utf8)
let phone = try JSONDecoder().decode(SavedSession.self, from: phoneFixture)
check(phone.kind == "Phone", "phone history without record ID or scores dictionary decodes")
check(phone.review.dimensions.count == 6, "phone history keeps all rubric dimensions")
check(phone.review.total == 70, "saved phone score matches server")
let objectionFixture = Data("""
{"id":"saved1","created_at":"2026-10-31T15:00:00Z","scenario":"objection_price","difficulty":"hard","language":"es","mode":"coaching","total_score":65,"scores":{"acknowledge":10,"discover":15,"respond":15,"trust":10,"next_step":15,"_review":{"real_concern":"Comparing incomplete quotes.","next_drill":"Compare complete offers.","feedback":{"discover":{"quote":"What is included?","evidence":"Asked a relevant question.","advice":"Listen to the answer."}}}},"conversation":[{"role":"salesperson","text":"What is included?"}]}
""".utf8)
let objection = try JSONDecoder().decode(SavedSession.self, from: objectionFixture)
check(objection.kind == "Objection Lab", "objection reviews are categorized correctly")
check(objection.review.dimensions.count == 5, "nested review metadata never becomes a numeric dimension")
check(objection.review.real_concern == "Comparing incomplete quotes.", "saved hidden-concern debrief is preserved")
check(objection.review.feedback?["discover"]?.quote == "What is included?", "saved rubric evidence survives decoding")
check(objection.review.mode == "coaching", "saved coached mode is preserved")
check(objection.conversation?.count == 1, "saved text transcript is available")
let review = try JSONDecoder().decode(TrainingReview.self, from: Data("{\"total\":65,\"scores\":{\"trust\":10},\"saved\":false,\"saveToken\":\"sealed-token\",\"save_warning\":\"Retry saving.\"}".utf8))
check(review.saveToken == "sealed-token" && review.saved == false, "save-only retry token survives decoding")
check(JSONValue.number(1e100).integer == nil, "untrusted oversized score cannot trap during conversion")
print("\(count) Swift origin, transcript, and review contract checks passed.")
