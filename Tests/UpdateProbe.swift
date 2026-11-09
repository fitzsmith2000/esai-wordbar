// Isolated Sparkle integration fixture. It never imports esai's scheduler or
// uses its bundle ID / preferences. Test feed and result path live in this bundle.
import AppKit
import Sparkle

final class Probe: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    var updater: SPUUpdater!
    var found = false
    let mode = Bundle.main.object(forInfoDictionaryKey:"ProbeMode") as! String
    let result = Bundle.main.object(forInfoDictionaryKey:"ProbeResult") as! String
    func finish(_ message: String, code: Int32 = 0) {
        try! Data(message.utf8).write(to:URL(fileURLWithPath:result))
        print(message)
        exit(code)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if mode == "installed" { finish("PASS automatic download, verification, installation and relaunch") }
        let driver = SPUStandardUserDriver(hostBundle:.main,delegate:nil)
        updater = SPUUpdater(hostBundle:.main,applicationBundle:.main,userDriver:driver,delegate:self)
        updater.automaticallyChecksForUpdates = false
        updater.automaticallyDownloadsUpdates = mode == "install"
        do { try updater.start() }
        catch { finish("FAIL start: \(error)",code:1) }
        if mode == "install" { updater.checkForUpdatesInBackground() }
        else { updater.checkForUpdateInformation() }
        DispatchQueue.main.asyncAfter(deadline:.now()+50) { self.finish("FAIL updater timeout",code:1) }
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { found = true }
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock install: @escaping () -> Void) -> Bool {
        // Only this isolated fixture installs immediately. Production lets Sparkle
        // wait for normal quit or offer its standard restart prompt.
        DispatchQueue.main.async { install() }
        return true
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        let error = error as NSError?
        if mode == "found", found, error == nil { finish("PASS newer version found in signed feed") }
        if mode == "current", !found, error?.code == Int(SUError.noUpdateError.rawValue) { finish("PASS current version does not update or downgrade") }
        if mode == "error", !found, let error, error.code != Int(SUError.noUpdateError.rawValue) { finish("PASS invalid/unavailable feed rejected: \(error.code)") }
        if mode == "install", error == nil { return } // installer continues after cycle
        finish("FAIL mode=\(mode) found=\(found) error=\(String(describing:error))",code:1)
    }
}
let application = NSApplication.shared
let delegate = Probe()
application.delegate = delegate
application.run()
