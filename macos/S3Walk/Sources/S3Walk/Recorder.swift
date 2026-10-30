// 録画：アプリの画面を音つきで動画にする。画面のコマと音を自分で受け取って、高画質で書き出す（AVAssetWriter）。
//   Mac：前にある窓（超球の窓・さんぽの窓など）だけを、アプリの音（風切り音・チリン・エンジン）ごと ScreenCaptureKit で録る（macOS 15 から）。
//        色は Display P3 のまま（あざやかな色がくすまない）。HEVC 10 bit（1 分で 200〜400 MB）、または最高画質の ProRes 4444（色を間引かない。ファイルはとても大きい）。
//        録っている間は Dock に「● 録画中」。空きが 5 GB を切ったら止めて保存する
//        動画は「ムービー／球面さんぽ」に .mov で。止めると Finder で見せる。初めての時は「画面とシステムオーディオ収録」の許可がいる
//   iPad・iPhone：画面を音ごと ReplayKit で受け取り、HEVC 10 bit・高いビットレートで書き出して、止めると写真に保存する
import SwiftUI
import AVFoundation
import VideoToolbox
#if os(macOS)
import AppKit
import ScreenCaptureKit
#else
import ReplayKit
import Photos
#endif

/// 動画の書き出し：最初のコマの大きさで作り、コマと音を順に足す（いつも同じ 1 本の糸で）
final class RecWriter: NSObject {
    let url: URL, prores: Bool, p3: Bool
    let q = DispatchQueue(label: "s3walk.rec")
    private var writer: AVAssetWriter? = nil
    private var vIn: AVAssetWriterInput? = nil, aIn: AVAssetWriterInput? = nil
    private var started = false, t0 = CMTime.zero
    private(set) var frames = 0
    init(url: URL, prores: Bool, p3: Bool) { self.url = url; self.prores = prores; self.p3 = p3 }

    private func setup(_ w: Int, _ h: Int, _ t: CMTime) {
        guard let wr = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }
        var vs: [String: Any] = [AVVideoWidthKey: w, AVVideoHeightKey: h]
        if prores {
            vs[AVVideoCodecKey] = AVVideoCodecType.proRes4444
        } else {
            // HEVC 10 bit（グラデーションのむらが出にくい）。ビットレートは画素の数に合わせて（Retina の窓で 1 秒 30 Mbit ほど。1 分で 200〜400 MB）
            let br = min(50_000_000, max(15_000_000, Int(Double(w * h) * 60 * 0.08)))
            vs[AVVideoCodecKey] = AVVideoCodecType.hevc
            vs[AVVideoCompressionPropertiesKey] = [AVVideoAverageBitRateKey: br, AVVideoExpectedSourceFrameRateKey: 60, AVVideoMaxKeyFrameIntervalKey: 120,
                                                   AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String]
        }
        // 色の印：Display P3（画面の広い色のまま。プレーヤーが正しい色で見せる）
        if p3 { vs[AVVideoColorPropertiesKey] = [AVVideoColorPrimariesKey: AVVideoColorPrimaries_P3_D65, AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2] }
        let vi = AVAssetWriterInput(mediaType: .video, outputSettings: vs); vi.expectsMediaDataInRealTime = true
        let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 256_000])
        ai.expectsMediaDataInRealTime = true
        if wr.canAdd(vi) { wr.add(vi) }; if wr.canAdd(ai) { wr.add(ai) }
        guard wr.startWriting() else { return }
        wr.startSession(atSourceTime: t)
        writer = wr; vIn = vi; aIn = ai; started = true; t0 = t
    }
    /// コマを 1 枚（この糸の上で呼ぶ）
    func video(_ sb: CMSampleBuffer) {
        guard let pb = sb.imageBuffer else { return }
        if !started { setup(CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb), sb.presentationTimeStamp) }
        guard started, let vi = vIn, vi.isReadyForMoreMediaData else { return }
        if vi.append(sb) { frames += 1 }
    }
    /// 音（最初のコマより前の音は捨てる）
    func audio(_ sb: CMSampleBuffer) {
        guard started, let ai = aIn, ai.isReadyForMoreMediaData, sb.presentationTimeStamp >= t0 else { return }
        ai.append(sb)
    }
    /// 書き終える（終わったら done。動画ができなかった時はエラー）
    func finish(_ done: @escaping (Error?) -> Void) {
        q.async {
            guard let wr = self.writer, self.started else { done(NSError(domain: "S3Walk", code: 2, userInfo: [NSLocalizedDescriptionKey: "コマが 1 枚も届きませんでした"])); return }
            self.vIn?.markAsFinished(); self.aIn?.markAsFinished()
            wr.finishWriting { done(wr.status == .completed ? nil : (wr.error ?? NSError(domain: "S3Walk", code: 3, userInfo: [NSLocalizedDescriptionKey: "書き出しに失敗しました"]))) }
        }
    }
}

#if os(macOS)
extension RecWriter: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sb.isValid else { return }
        switch type {
        case .screen:
            // 中身のあるコマだけ（画面が変わらない時は、印だけのコマが来る）
            guard let att = (CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
                  let raw = att[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
            video(sb)
        case .audio: audio(sb)
        default: break
        }
    }
}
#endif

@MainActor final class Recorder: ObservableObject {
    static let shared = Recorder()
    @Published private(set) var recording = false
    @Published private(set) var busy = false
    @Published var message: String? = nil                              // 知らせ（保存した所・できなかった理由）
    @Published var prores = UserDefaults.standard.bool(forKey: "s3walk.rec.prores") { didSet { UserDefaults.standard.set(prores, forKey: "s3walk.rec.prores") } }   // Mac：最高画質（ProRes 4444。ファイルは大きい）
    private(set) var started = Date()
    private var rw: RecWriter? = nil
    private var watch: Task<Void, Never>? = nil
    private var stopNote = ""                                          // 自分で止めた理由（空きが少ない時など）

    /// 録っている間の見張り：空きが 5 GB を切ったら止めて保存する。Mac は Dock のアイコンに「● 録画中」
    private func beginWatch() {
        #if os(macOS)
        NSApp.dockTile.badgeLabel = "● 録画中"
        #endif
        watch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, self.recording else { return }
                let home = URL(fileURLWithPath: NSHomeDirectory())
                if let free = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage, free < 5_000_000_000 {
                    self.stopNote = "空きが 5 GB を切ったので、録画を止めました。\n"; self.stop(); return
                }
            }
        }
    }
    private func endWatch() {
        watch?.cancel(); watch = nil
        #if os(macOS)
        NSApp.dockTile.badgeLabel = nil
        #endif
    }

    func toggle() { recording ? stop() : start() }

    /// 動画の名前：球面さんぽ_年月日_時分秒.mov
    private func fileName() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd_HHmmss"
        return "球面さんぽ_\(f.string(from: Date())).mov"
    }

    #if os(macOS)
    private var stream: SCStream? = nil

    func start() {
        guard !busy, !recording else { return }
        guard #available(macOS 15.0, *) else { message = "録画は macOS 15 から使えます"; return }
        busy = true
        let win = NSApp.keyWindow ?? NSApp.mainWindow
        let wid = win.map { CGWindowID($0.windowNumber) }, scale = win?.backingScaleFactor ?? 2
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let pid = ProcessInfo.processInfo.processIdentifier
                guard let w = content.windows.first(where: { $0.windowID == wid }) ?? content.windows.first(where: { $0.owningApplication?.processID == pid && $0.frame.width > 200 }) else {
                    throw NSError(domain: "S3Walk", code: 1, userInfo: [NSLocalizedDescriptionKey: "録る窓が見つかりません"])
                }
                let filter = SCContentFilter(desktopIndependentWindow: w)
                let cfg = SCStreamConfiguration()
                cfg.width = Int(w.frame.width * scale) / 2 * 2; cfg.height = Int(w.frame.height * scale) / 2 * 2   // Retina の画素のまま（偶数に）
                cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                cfg.pixelFormat = kCVPixelFormatType_32BGRA                   // 色を間引かずに受け取る
                cfg.colorSpaceName = CGColorSpace.displayP3                   // 画面の広い色のまま
                cfg.showsCursor = false
                cfg.queueDepth = 8
                cfg.capturesAudio = true; cfg.excludesCurrentProcessAudio = false; cfg.sampleRate = 48000; cfg.channelCount = 2
                let dir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("球面さんぽ", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let wr = RecWriter(url: dir.appendingPathComponent(fileName()), prores: prores, p3: true)
                let st = SCStream(filter: filter, configuration: cfg, delegate: nil)
                try st.addStreamOutput(wr, type: .screen, sampleHandlerQueue: wr.q)
                try st.addStreamOutput(wr, type: .audio, sampleHandlerQueue: wr.q)
                try await st.startCapture()
                stream = st; rw = wr; started = Date(); recording = true; busy = false; beginWatch()
            } catch {
                busy = false
                message = "録画を始められませんでした：\(error.localizedDescription)\n初めての時は、システム設定 → プライバシーとセキュリティ → 画面とシステムオーディオ収録 で「球面さんぽ」を許可して、アプリを開き直してください"
                CGRequestScreenCaptureAccess()
            }
        }
    }

    func stop() {
        guard recording, let st = stream, let wr = rw else { return }
        busy = true; endWatch()
        Task {
            try? await st.stopCapture()
            stream = nil
            wr.finish { err in
                Task { @MainActor in
                    self.rw = nil; self.recording = false; self.busy = false
                    if let err { self.message = "動画を書き出せませんでした：\(err.localizedDescription)"; return }
                    self.message = self.stopNote + "動画を保存しました（\(wr.frames) コマ）：\(wr.url.path)"; self.stopNote = ""
                    NSWorkspace.shared.activateFileViewerSelecting([wr.url])
                }
            }
        }
    }
    #else
    func start() {
        guard !busy, !recording else { return }
        let r = RPScreenRecorder.shared()
        guard r.isAvailable else { message = "この端末では録画できません"; return }
        r.isMicrophoneEnabled = false
        busy = true
        let wr = RecWriter(url: FileManager.default.temporaryDirectory.appendingPathComponent(fileName()), prores: false, p3: false)
        rw = wr
        r.startCapture(handler: { sb, type, err in
            guard err == nil, sb.isValid else { return }
            wr.q.sync {
                switch type {
                case .video: wr.video(sb)
                case .audioApp: wr.audio(sb)
                default: break                                          // マイクの音は入れない
                }
            }
        }, completionHandler: { err in
            Task { @MainActor in
                self.busy = false
                if let err { self.rw = nil; self.message = "録画を始められませんでした：\(err.localizedDescription)" }
                else { self.started = Date(); self.recording = true; self.beginWatch() }
            }
        })
    }

    func stop() {
        guard recording, let wr = rw else { return }
        busy = true; endWatch()
        RPScreenRecorder.shared().stopCapture { _ in
            wr.finish { err in
                Task { @MainActor in
                    self.rw = nil; self.recording = false
                    if let err { self.busy = false; self.message = "動画を書き出せませんでした：\(err.localizedDescription)"; return }
                    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                        guard status == .authorized || status == .limited else {
                            Task { @MainActor in self.busy = false; self.message = "写真に保存する許可がありません（設定 → 球面さんぽ → 写真）" }
                            return
                        }
                        PHPhotoLibrary.shared().performChanges({ _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: wr.url) }) { ok, e in
                            Task { @MainActor in
                                self.busy = false
                                self.message = self.stopNote + (ok ? "動画を写真に保存しました（\(wr.frames) コマ）" : "写真に保存できませんでした：\(e?.localizedDescription ?? "")"); self.stopNote = ""
                                try? FileManager.default.removeItem(at: wr.url)
                            }
                        }
                    }
                }
            }
        }
    }
    #endif
}

#if os(macOS)
/// メニューの「録画」：前の窓を録り始める／止める（⌘⇧R）、最高画質（ProRes）
struct RecordMenuItem: View {
    @ObservedObject var rec = Recorder.shared
    var body: some View {
        Button(rec.recording ? "録画を止めて保存" : "前の窓を録画する") { rec.toggle() }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(rec.busy)
        Toggle("最高画質（ProRes 4444・ファイルが大きい）", isOn: $rec.prores).disabled(rec.recording)
    }
}
#endif

/// 録画のボタン：● 録画 ／ ■ 止める（録っている間は赤く、経った時間）。知らせは下に出る
struct RecordButton: View {
    @ObservedObject var rec = Recorder.shared
    var body: some View {
        Button { rec.toggle() } label: {
            if rec.recording {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let s = Int(Date().timeIntervalSince(rec.started))
                    Label(String(format: "止める %d:%02d", s / 60, s % 60), systemImage: "stop.circle.fill").foregroundStyle(.red)
                }
            } else {
                Label("録画", systemImage: "record.circle")
            }
        }
        .font(.caption).disabled(rec.busy)
        .help("この窓を音（風切り音・チリン）ごと高画質の動画に録る（色は Display P3 のまま・60 コマ）。もう一度押すと止めて保存（Mac：ムービー／球面さんぽ。iPad・iPhone：写真）。Mac は ⌘⇧R でも、メニューの「録画」で最高画質（ProRes）も")
        .alert(rec.message ?? "", isPresented: Binding(get: { rec.message != nil }, set: { if !$0 { rec.message = nil } })) { Button("OK") { rec.message = nil } }
    }
}
