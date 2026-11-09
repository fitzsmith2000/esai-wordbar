import AppKit
import SwiftUI
import Combine
import Sparkle

/// Sparkle owns downloading, signature verification, replacement and relaunch.
/// Preview/test instances never start a scheduler or read/write real preferences.
final class UpdateService: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    @Published private(set) var automaticUpdates: Bool
    @Published private(set) var canCheck = false
    @Published private(set) var errorMessage: String?
    var willPresentUpdate: (() -> Void)?
    let enabled: Bool
    private let defaults: UserDefaults
    private var controller: SPUStandardUpdaterController?
    private var observations: [NSKeyValueObservation] = []

    init(enabled: Bool, defaults: UserDefaults = .standard) {
        self.enabled = enabled
        self.defaults = defaults
        // A single preference controls the complete background update flow.
        // Preserve an existing opt-in; checking-only preferences migrate to off.
        let checks = enabled && (defaults.object(forKey:"SUEnableAutomaticChecks") as? Bool ?? false)
        let installs = enabled && (defaults.object(forKey:"SUAutomaticallyUpdate") as? Bool ?? false)
        automaticUpdates = checks && installs
        super.init()
    }

    func start() {
        guard enabled, controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:self,userDriverDelegate:self)
        self.controller = controller
        let updater = controller.updater
        setAutomaticUpdates(automaticUpdates)
        updater.updateCheckInterval = 3_600
        observations = [
            updater.observe(\.canCheckForUpdates,options:[.initial,.new]) { [weak self] updater,_ in
                DispatchQueue.main.async { self?.canCheck = updater.canCheckForUpdates }
            },
            updater.observe(\.automaticallyChecksForUpdates,options:[.new]) { [weak self] updater,_ in
                DispatchQueue.main.async { self?.setAutomaticUpdates(updater.automaticallyChecksForUpdates) }
            },
            updater.observe(\.automaticallyDownloadsUpdates,options:[.new]) { [weak self] updater,_ in
                DispatchQueue.main.async { self?.setAutomaticUpdates(updater.automaticallyDownloadsUpdates) }
            }
        ]
        do { try updater.start() }
        catch { errorMessage = error.localizedDescription }
    }

    func checkForUpdates() {
        guard enabled, canCheck else { return }
        errorMessage = nil
        willPresentUpdate?()
        NSApp.activate(ignoringOtherApps:true)
        controller?.checkForUpdates(nil)
    }

    func standardUserDriverWillShowModalAlert() { willPresentUpdate?() }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if handleShowingUpdate { willPresentUpdate?() }
    }

    func setAutomaticUpdates(_ value: Bool) {
        guard enabled else { return }
        if automaticUpdates != value { automaticUpdates = value }
        // Equality guards prevent KVO feedback when Sparkle's native window
        // changes its own update preference. Either entry controls both flags.
        if let updater = controller?.updater {
            if updater.automaticallyChecksForUpdates != value { updater.automaticallyChecksForUpdates = value }
            if updater.automaticallyDownloadsUpdates != value { updater.automaticallyDownloadsUpdates = value }
        }
        defaults.set(value,forKey:"SUEnableAutomaticChecks")
        defaults.set(value,forKey:"SUAutomaticallyUpdate")
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        // 'No update available' is a successful check, not a transport failure.
        if let error = error as NSError?, !(error.domain == SUSparkleErrorDomain && error.code == Int(SUError.noUpdateError.rawValue)) {
            errorMessage = error.localizedDescription
        } else { errorMessage = nil }
    }

    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool { false }
}

struct UpdateControls: View {
    @ObservedObject var service: UpdateService

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("软件更新").font(.headline)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("自动更新").font(.callout.weight(.medium))
                    Text("定期检查并下载；退出应用时安装更新。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("自动更新", isOn: Binding(
                    get: { service.automaticUpdates },
                    set: { service.setAutomaticUpdates($0) }
                )).labelsHidden()
            }
            .padding(12)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Text("当前版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("检查更新…") { service.checkForUpdates() }
                    .buttonStyle(.bordered)
                    .disabled(!service.canCheck)
            }
            if let error = service.errorMessage {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
    }
}
