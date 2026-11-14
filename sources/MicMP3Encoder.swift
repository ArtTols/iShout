import AVFoundation

enum EncoderError: LocalizedError {
    case lame, noInput, converter
    var errorDescription: String? {
        switch self {
        case .lame: return "Could not initialise the LAME MP3 encoder."
        case .noInput: return "No audio input available."
        case .converter: return "Could not convert the microphone format."
        }
    }
}

/// Captures the microphone with AVAudioEngine and encodes it to MP3 with LAME.
final class MicMP3Encoder {
    struct Settings { var bitrate: Int; var sampleRate: Double; var stereo: Bool }

    var onMP3: ((Data) -> Void)?
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "encoder")
    private var lame: lame_t?
    private var converter: AVAudioConverter?
    private var outFormat: AVAudioFormat?
    private var settings: Settings?
    private var observer: NSObjectProtocol?

    func start(_ s: Settings) throws {
        settings = s
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        guard let l = lame_init() else { throw EncoderError.lame }
        lame_set_in_samplerate(l, Int32(s.sampleRate))
        lame_set_out_samplerate(l, Int32(s.sampleRate))
        lame_set_num_channels(l, s.stereo ? 2 : 1)
        lame_set_mode(l, s.stereo ? JOINT_STEREO : MONO)
        lame_set_brate(l, Int32(s.bitrate))
        lame_set_VBR(l, vbr_off)
        lame_set_quality(l, 2)
        if lame_init_params(l) < 0 { lame_close(l); throw EncoderError.lame }
        lame = l

        try startEngine()

        // Restart when the route changes (USB mic plugged in, etc.)
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self = self, self.settings != nil else { return }
            self.engine.inputNode.removeTap(onBus: 0)
            self.engine.stop()
            try? self.startEngine()
        }
    }

    private func startEngine() throws {
        guard let s = settings else { return }
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else { throw EncoderError.noInput }
        guard let out = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: s.sampleRate,
                                      channels: s.stereo ? 2 : 1, interleaved: false),
              let conv = AVAudioConverter(from: inFormat, to: out) else { throw EncoderError.converter }
        queue.sync { converter = conv; outFormat = out }
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buf, _ in
            self?.queue.async { self?.process(buf) }
        }
        engine.prepare()
        try engine.start()
    }

    private func process(_ buf: AVAudioPCMBuffer) {
        guard let conv = converter, let out = outFormat, let l = lame else { return }

        if let ch = buf.floatChannelData?[0] {
            let n = Int(buf.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += ch[i] * ch[i] }
            onLevel?(min(1, sqrt(sum / Float(max(n, 1))) * 4))
        }

        let ratio = out.sampleRate / buf.format.sampleRate
        let cap = AVAudioFrameCount(Double(buf.frameLength) * ratio) + 64
        guard let pcm = AVAudioPCMBuffer(pcmFormat: out, frameCapacity: cap) else { return }
        var supplied = false
        var err: NSError?
        conv.convert(to: pcm, error: &err) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buf
        }
        let n = Int32(pcm.frameLength)
        guard err == nil, n > 0, let data = pcm.floatChannelData else { return }

        let left = data[0]
        let right = out.channelCount > 1 ? data[1] : data[0]
        let size = Int(Double(n) * 1.25) + 7200
        var mp3 = [UInt8](repeating: 0, count: size)
        let written = lame_encode_buffer_ieee_float(l, left, right, n, &mp3, Int32(size))
        if written > 0 { onMP3?(Data(mp3[0..<Int(written)])) }
    }

    func stop() {
        if let o = observer { NotificationCenter.default.removeObserver(o); observer = nil }
        settings = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        queue.sync {
            if let l = lame {
                var buf = [UInt8](repeating: 0, count: 7200)
                let n = lame_encode_flush(l, &buf, 7200)
                if n > 0 { onMP3?(Data(buf[0..<Int(n)])) }
                lame_close(l)
                lame = nil
            }
            converter = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
