import Foundation
import Combine
import AVFoundation
import WebRTC
import ObjectionIQCore

@MainActor
final class NativeCall: NSObject, ObservableObject {
    enum Stage { case idle, connecting, connected, ended, scoring, review }
    @Published var stage = Stage.idle
    @Published var status = "Ready to practice"
    @Published var error: String?
    @Published var muted = false
    @Published var speaker = true
    @Published var transcript = CallTranscript()
    @Published var review: TrainingReview?
    @Published var connectedAt: Date?
    @Published var endedAt: Date?
    let settings: PracticeSettings
    private let api: NativeAPI
    private var peer: RTCPeerConnection?
    private var channel: RTCDataChannel?
    private var microphone: RTCAudioTrack?
    private var generation = UUID()
    private var timeout: Task<Void, Never>?
    private var audioActive = false
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
    }()
    init(api: NativeAPI, settings: PracticeSettings) { self.api = api; self.settings = settings; super.init() }
    var isLive: Bool { stage == .connecting || stage == .connected }

    func start() async {
        guard stage == .idle else { return }
        stage = .connecting; status = "Preparing your microphone…"; error = nil
        let current = generation
        do {
            let allowed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                if #available(iOS 17, *) { AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) } }
                else { AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) } }
            }
            guard generation == current, !Task.isCancelled else { return }
            guard allowed else { throw TrainerError.message("Microphone access is off. Open Settings → ObjectionIQ → Microphone, then start a new call.") }
            try configureAudio()

            let configuration = RTCConfiguration()
            configuration.sdpSemantics = .unifiedPlan
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            guard let connection = Self.factory.peerConnection(with: configuration, constraints: constraints, delegate: self) else {
                throw TrainerError.message("Could not prepare the audio connection.")
            }
            peer = connection
            let source = Self.factory.audioSource(with: constraints)
            let track = Self.factory.audioTrack(with: source, trackId: "microphone")
            microphone = track
            connection.add(track, streamIds: ["training-audio"])
            let channelConfig = RTCDataChannelConfiguration()
            channelConfig.isOrdered = true
            channel = connection.dataChannel(forLabel: "oai-events", configuration: channelConfig)
            guard let channel else { throw TrainerError.message("Could not prepare live captions.") }
            channel.delegate = self
            status = "Connecting your customer…"
            let offer = try await withCheckedThrowingContinuation { (c: CheckedContinuation<RTCSessionDescription, Error>) in
                connection.offer(for: RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true"], optionalConstraints: nil)) { offer, error in
                    if let error { c.resume(throwing: error) }
                    else if let offer { c.resume(returning: offer) }
                    else { c.resume(throwing: TrainerError.message("Could not create the audio offer.")) }
                }
            }
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                connection.setLocalDescription(offer) { error in
                    if let error { c.resume(throwing: error) } else { c.resume() }
                }
            }
            for _ in 0..<100 {
                guard generation == current else { return }
                if connection.iceGatheringState == .complete { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard generation == current, !Task.isCancelled else { return }
            guard connection.iceGatheringState == .complete, let sdp = connection.localDescription?.sdp else {
                throw TrainerError.message("Audio connection timed out. Try another network and start a new call.")
            }
            var body: [String: Any] = settings.body
            body["sdp"] = sdp
            let answer = try await api.data("/api/session", body: body)
            guard generation == current, !Task.isCancelled else { return }
            guard let answerSDP = String(data: answer, encoding: .utf8), answerSDP.hasPrefix("v=") else {
                throw TrainerError.message("The server did not return a valid voice connection.")
            }
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                connection.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: answerSDP)) { error in
                    if let error { c.resume(throwing: error) } else { c.resume() }
                }
            }
            timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                guard let self, !Task.isCancelled, self.generation == current, self.stage == .connecting else { return }
                self.stop(reason: "The voice connection timed out. Please start a new call.")
            }
        } catch {
            guard generation == current else { return }
            stop(reason: error.localizedDescription)
        }
    }
    private func configureAudio() throws {
        let audio = RTCAudioSession.sharedInstance()
        audio.useManualAudio = true
        audio.lockForConfiguration()
        defer { audio.unlockForConfiguration() }
        let config = RTCAudioSessionConfiguration.webRTC()
        config.category = AVAudioSession.Category.playAndRecord.rawValue
        config.mode = AVAudioSession.Mode.voiceChat.rawValue
        config.categoryOptions = [.allowBluetooth, .defaultToSpeaker]
        RTCAudioSessionConfiguration.setWebRTC(config)
        try audio.setConfiguration(config, active: true)
        audioActive = true; audio.isAudioEnabled = true

    }
    func setMuted(_ value: Bool) { muted = value; microphone?.isEnabled = !value }
    func toggleSpeaker() {
        let audio = RTCAudioSession.sharedInstance(); audio.lockForConfiguration(); defer { audio.unlockForConfiguration() }
        do { try audio.overrideOutputAudioPort(speaker ? .none : .speaker); speaker.toggle() }
        catch { self.error = "Could not change the audio route. Check your headphones or Bluetooth connection." }
    }
    func stop(reason: String? = nil) {
        generation = UUID(); timeout?.cancel(); timeout = nil
        microphone?.isEnabled = false
        channel?.delegate = nil; channel?.close(); channel = nil
        peer?.delegate = nil; peer?.close(); peer = nil; microphone = nil
        if audioActive {
            let audio = RTCAudioSession.sharedInstance(); audio.lockForConfiguration()
            audio.isAudioEnabled = false; try? audio.setActive(false)
            audio.unlockForConfiguration(); audioActive = false
        }
        if endedAt == nil { endedAt = Date() }
        if stage != .review && stage != .scoring { stage = .ended }
        if let reason { error = reason }
        status = "Call ended"
    }
    func endAndScore() async {
        guard stage != .scoring && stage != .review else { return }
        if isLive {
            status = "Finishing captions…"; setMuted(true)
            // Allow the provider's final VAD/transcription events to arrive before releasing WebRTC.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        stop()
        guard transcript.canScore else { error = "There is not enough transcribed conversation to score yet. Start a new call and exchange a few sentences."; return }
        stage = .scoring; error = nil
        let current = generation
        var body: [String: Any] = settings.body
        body["transcript"] = transcript.turns.map { ["speaker": $0.speaker, "text": $0.text] }
        do {
            let result: TrainingReview = try await api.request("/api/score", body: body)
            guard current == generation else { return }
            review = result; stage = .review
        } catch {
            guard current == generation else { return }
            stage = .ended; self.error = error.localizedDescription
        }
    }
    private func receive(_ data: Data) {
        try? transcript.receive(data)
        guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = event["type"] as? String else { return }
        switch type {
        case "output_audio_buffer.started": status = "Customer speaking"
        case "output_audio_buffer.stopped", "output_audio_buffer.cleared": status = "Your turn to speak"
        case "error": error = "The voice service reported a problem. You can end the call and score the available transcript."
        default: break
        }
    }
}

extension NativeCall: RTCPeerConnectionDelegate, RTCDataChannelDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor [weak self] in
            guard let self, self.peer === peerConnection else { return }
            if newState == .failed || newState == .disconnected { self.stop(reason: "The connection was interrupted. End & Score preserves the available conversation.") }
        }
    }
    nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        Task { @MainActor [weak self] in
            guard let self, self.channel === dataChannel else { return }
            if dataChannel.readyState == .open {
                self.timeout?.cancel(); self.stage = .connected; self.connectedAt = Date(); self.status = "Your turn to speak"
            } else if dataChannel.readyState == .closed, self.isLive {
                self.stop(reason: "The live call ended. You can score the available conversation.")
            }
        }
    }
    nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        let data = buffer.data
        Task { @MainActor [weak self] in
            guard let self, self.channel === dataChannel else { return }; self.receive(data)
        }
    }
}
