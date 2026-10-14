// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import SwiftUI
import AppKit
import CryptoKit
import Security

struct ReleaseUpdate: Decodable, Sendable {
    struct Asset: Decodable, Sendable {
        let name: String
        let size: Int
        let browser_download_url: URL
        let digest: String?
    }
    let tag_name: String
    let name: String?
    let body: String?
    let prerelease: Bool
    let draft: Bool
    let assets: [Asset]?
    var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
    var pageURL: URL? {
        guard Self.parts(tag_name) != nil else { return nil }
        return URL(string: "https://github.com/Davud77/BotPlus-PDF-Editor/releases/tag/" + tag_name)
    }
    var archive: Asset? {
        assets?.first { $0.name == "BotPlus-PDF-Editor-update.zip" && (1...128*1024*1024).contains($0.size) && Self.assetURL($0.browser_download_url, tag: tag_name) }
    }
    static func parts(_ value: String) -> [Int]? {
        let clean = value.hasPrefix("v") ? String(value.dropFirst()) : value
        guard clean.count <= 32, clean.range(of: "^[0-9]+(?:\\.[0-9]+){1,2}$",options: .regularExpression) != nil else { return nil }
        let fields = clean.split(separator: "."), numbers = fields.compactMap { Int($0) }
        guard numbers.count == fields.count else { return nil }
        return Array((numbers + [0,0,0]).prefix(3))
    }
    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        guard let a = parts(candidate), let b = parts(installed) else { return false }
        for (x,y) in zip(a,b) where x != y { return x > y }; return false
    }
    static func assetURL(_ url: URL, tag: String) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.user == nil && url.password == nil && url.port == nil && url.query == nil && url.fragment == nil && url.path.hasPrefix("/Davud77/BotPlus-PDF-Editor/releases/download/" + tag + "/")
    }
    static func permittedDownload(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && url.port == nil && ["github.com","release-assets.githubusercontent.com","objects.githubusercontent.com"].contains(url.host ?? "")
    }
}

struct UpdatePolicy {
    var skipped: String?
    var snoozedUntil: Date?
    func shouldNotify(version: String, installed: String, now: Date = Date()) -> Bool {
        ReleaseUpdate.isNewer(version,than: installed) && ReleaseUpdate.parts(version) != skipped.flatMap(ReleaseUpdate.parts) && (snoozedUntil == nil || snoozedUntil! <= now)
    }
    static func month(after date: Date, calendar: Calendar = .current) -> Date { calendar.date(byAdding: .month,value: 1,to: date) ?? date.addingTimeInterval(30*86400) }
}

enum UpdateFailure: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

// ZIP central directory preflight: no ZIP64, symlinks, traversal or oversized output.
// The archive is additionally pinned to the SHA-256 returned by GitHub Releases.
enum UpdateArchive {
    static func validate(_ data: Data) throws {
        func fail() throws -> Never { throw UpdateFailure.invalid("Небезопасный или неподдерживаемый ZIP / Unsafe or unsupported ZIP") }
        let bytes = [UInt8](data)
        func n(_ offset: Int, _ count: Int) -> UInt64 {
            guard offset >= 0, offset + count <= bytes.count else { return UInt64.max }
            return (0..<count).reduce(0) { $0 | UInt64(bytes[offset + $1]) << ($1*8) }
        }
        guard bytes.count >= 22, bytes.count <= 128*1024*1024 else { try fail() }
        let first = max(0,bytes.count-65557)
        guard let end = stride(from: bytes.count-22, through: first, by: -1).first(where: { n($0,4) == 0x06054b50 && $0+22+Int(n($0+20,2)) == bytes.count }) else { try fail() }
        let count = Int(n(end+10,2)), start = Int(n(end+16,4)), length = Int(n(end+12,4))
        guard n(end+4,2) == 0, n(end+6,2) == 0, n(end+8,2) == UInt64(count), (1...20000).contains(count), start >= 0, start+length == end else { try fail() }
        var offset = start, total: UInt64 = 0, seen = Set<String>()
        for _ in 0..<count {
            guard offset+46 <= end, n(offset,4) == 0x02014b50 else { try fail() }
            let size = n(offset+24,4), nameCount = Int(n(offset+28,2)), extra = Int(n(offset+30,2)), comment = Int(n(offset+32,2)), local = Int(n(offset+42,4))
            let next = offset+46+nameCount+extra+comment, mode = (n(offset+38,4) >> 16) & 0xf000
            guard next <= end, nameCount > 0, size != 0xffffffff, n(offset+20,4) != 0xffffffff,
                  n(offset+34,2) == 0, n(offset+8,2) & 1 == 0, [0,0x8000,0x4000].contains(mode),
                  [0,8].contains(n(offset+10,2)), local+30 <= start, n(local,4) == 0x04034b50,
                  let name = String(bytes: bytes[(offset+46)..<(offset+46+nameCount)],encoding: .utf8),
                  name == "BotPlus PDF Editor.app/" || name.hasPrefix("BotPlus PDF Editor.app/"),
                  !name.contains("\\"), !name.unicodeScalars.contains(where: { $0.value < 32 }),
                  !name.split(separator: "/",omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." }), seen.insert(name).inserted else { try fail() }
            let localName = Int(n(local+26,2)), localExtra = Int(n(local+28,2)), localEnd = local+30+localName+localExtra
            guard localName == nameCount, localEnd <= start,
                  bytes[(local+30)..<(local+30+localName)].elementsEqual(bytes[(offset+46)..<(offset+46+nameCount)]),
                  UInt64(localEnd)+n(offset+20,4) <= UInt64(start) else { try fail() }
            total += size; guard total <= 512*1024*1024 else { try fail() }
            offset = next
        }
        guard offset == end, seen.contains("BotPlus PDF Editor.app/Contents/Info.plist") else { try fail() }
    }
    static func checksum(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x",$0) }.joined() }
    static func validDigest(_ digest: String?) -> String? {
        guard let digest, digest.hasPrefix("sha256:") else { return nil }
        let hex = String(digest.dropFirst(7)).lowercased()
        return hex.range(of: "^[0-9a-f]{64}$",options: .regularExpression) != nil ? hex : nil
    }
}

final class UpdateTransferDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void
    private let api: Bool
    private let lock = NSLock()
    private var previous = Date.distantPast
    init(api: Bool = false, progress: @escaping @Sendable (Double) -> Void) { self.api = api; self.progress = progress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) { }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,totalBytesWritten: Int64,totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > 128*1024*1024 { downloadTask.cancel(); return }
        lock.lock(); let now = Date(), notify = now.timeIntervalSince(previous) > 0.1; if notify { previous = now }; lock.unlock()
        if notify, totalBytesExpectedToWrite > 0 { progress(min(1,Double(totalBytesWritten)/Double(totalBytesExpectedToWrite))) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        let valid = request.url.map { url in
            api ? url.scheme == "https" && url.host == "api.github.com" && url.user == nil && url.password == nil && url.port == nil : ReleaseUpdate.permittedDownload(url)
        } == true
        completionHandler(valid ? request : nil)
    }
}

enum UpdateInstaller {
    static func bundleVersion(_ app: URL) throws -> String? {
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard data.count < 256*1024 else { throw UpdateFailure.invalid("Неверный Info.plist / Invalid Info.plist") }
        return (try PropertyListSerialization.propertyList(from: data,format: nil) as? [String:Any])?["CFBundleShortVersionString"] as? String
    }
    static func validate(app: URL, version: String, current: URL) throws {
        guard ReleaseUpdate.parts(version) != nil, let bundle = Bundle(url: app), bundle.bundleIdentifier == "com.botplus.pdfeditor",
              let actual = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              ReleaseUpdate.parts(actual) == ReleaseUpdate.parts(version), let executable = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else { throw UpdateFailure.invalid("Неверная программа или версия / Invalid application or version") }
        func signature(_ url: URL) throws -> String? {
            var code: SecStaticCode?
            guard SecStaticCodeCreateWithPath(url as CFURL,[],&code) == errSecSuccess, let code,
                  SecStaticCodeCheckValidity(code,SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode),nil) == errSecSuccess else { throw UpdateFailure.invalid("Повреждена подпись программы / Invalid code signature") }
            var info: CFDictionary?
            guard SecCodeCopySigningInformation(code,SecCSFlags(rawValue: kSecCSSigningInformation),&info) == errSecSuccess else { throw UpdateFailure.invalid("Нет данных подписи / Missing signature information") }
            return (info as? [String:Any])?[kSecCodeInfoTeamIdentifier as String] as? String
        }
        let nextTeam = try signature(app), oldTeam = try signature(current)
        // A future Developer ID release must retain its publisher's Team ID.
        if let oldTeam, oldTeam != nextTeam { throw UpdateFailure.invalid("Изменился издатель программы / Publisher changed") }
        let handle = try FileHandle(forReadingFrom: executable); defer { try? handle.close() }
        let header = [UInt8](try handle.read(upToCount: 4096) ?? Data())
        func word(_ offset: Int) -> UInt32? {
            guard offset+4 <= header.count else { return nil }
            return (0..<4).reduce(0) { ($0 << 8) | UInt32(header[offset+$1]) }
        }
        guard let magic = word(0), magic == 0xcafebabe || magic == 0xcafebabf, let count = word(4), (2...16).contains(count) else { throw UpdateFailure.invalid("Обновление не является универсальной сборкой / Update is not universal") }
        let stride = magic == 0xcafebabf ? 32 : 20
        let architectures = Set((0..<Int(count)).compactMap { word(8+$0*stride) })
        guard architectures.contains(0x01000007), architectures.contains(0x0100000c) else { throw UpdateFailure.invalid("Обновление не поддерживает Intel и Apple Silicon / Update does not support both architectures") }
    }
    static func swap(next: URL, current: URL, backup: URL, move: (URL,URL) throws -> Void = { try FileManager.default.moveItem(at: $0,to: $1) }) throws {
        try move(current,backup)
        do { try move(next,current) }
        catch {
            let original = error
            do { try move(backup,current) }
            catch { throw UpdateFailure.invalid("Откат не завершён. Предыдущая программа: \(backup.path) / Rollback failed; previous app remains at this path") }
            throw original
        }
    }

    static func unpack(archive: URL, directory: URL, version: String, current: URL) throws -> URL {
        let data = try Data(contentsOf: archive); try UpdateArchive.validate(data)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: false)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto"); process.arguments = ["-x","-k",archive.path,directory.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); try Task.checkCancellation()
        guard process.terminationStatus == 0 else { throw UpdateFailure.invalid("Не удалось распаковать обновление / Extraction failed") }
        let app = directory.appendingPathComponent("BotPlus PDF Editor.app",isDirectory: true)
        try validate(app: app,version: version,current: current); return app
    }
    // Called only during explicit termination, after document recovery completes.
    // Copy first, rename on the same volume, retain the previous app for rollback.
    static func install(staged: URL, current: URL, folder: URL, version: String) throws {
        let fm = FileManager.default, target = current.standardizedFileURL
        guard folder.standardizedFileURL == target.deletingLastPathComponent(), target.pathExtension == "app",
              fm.isWritableFile(atPath: folder.path), !target.path.contains("/AppTranslocation/"), !target.path.hasPrefix("/Volumes/") else { throw UpdateFailure.invalid("Выберите папку установленного приложения; сначала скопируйте его с DMG / Choose the installed app folder; copy the app from DMG first") }
        guard let installed = try bundleVersion(current), ReleaseUpdate.isNewer(version,than: installed) else { throw UpdateFailure.invalid("Обновление не новее установленной версии / Update is not newer than installed version") }
        try validate(app: staged,version: version,current: current)
        let next = folder.appendingPathComponent(".BotPlus-update-"+UUID().uuidString+".app")
        let backup = folder.appendingPathComponent("BotPlus PDF Editor.previous-"+UUID().uuidString+".app")
        defer { try? fm.removeItem(at: next) }
        try fm.copyItem(at: staged,to: next)
        try validate(app: next,version: version,current: current)
        try swap(next: next,current: target,backup: backup)
        // Backup deliberately retained; its path is shown after the next launch.
        UserDefaults.standard.set(backup.path,forKey: "BotPlus.update.previousApp")
    }
}

@MainActor
final class AppUpdateController: ObservableObject {
    static let shared = AppUpdateController(installed: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.7")
    private let defaults: UserDefaults
    let installed: String
    @Published var automaticChecks: Bool { didSet { defaults.set(automaticChecks,forKey: "BotPlus.update.checks") } }
    @Published var automaticInstall: Bool { didSet { defaults.set(automaticInstall,forKey: "BotPlus.update.install"); if !automaticInstall { disarm() }; if automaticInstall, let release, policy.shouldNotify(version: release.tag_name,installed: installed) { download() } } }
    @Published private(set) var policy: UpdatePolicy
    @Published private(set) var checking = false
    @Published private(set) var release: ReleaseUpdate?
    @Published private(set) var error: String?
    @Published private(set) var progress: Double?
    @Published private(set) var staged: URL?
    @Published private(set) var installationArmed = false
    @Published private(set) var installing = false
    var onAvailable: (() -> Void)?
    private var task: Task<Void,Never>?
    private var schedule: Task<Void,Never>?
    private var lease: URL?
    private var folder: URL?
    private var notifiedVersion: String?
    private var transferID: UUID?
    init(installed: String, defaults: UserDefaults = .standard) {
        self.installed = installed; self.defaults = defaults
        automaticChecks = defaults.object(forKey: "BotPlus.update.checks") as? Bool ?? true
        automaticInstall = defaults.bool(forKey: "BotPlus.update.install")
        policy = UpdatePolicy(skipped: defaults.string(forKey: "BotPlus.update.skipped"),snoozedUntil: defaults.object(forKey: "BotPlus.update.snooze") as? Date)
    }
    func start() {
        guard schedule == nil else { return }
        schedule = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            while !Task.isCancelled {
                guard let self else { return }
                if self.automaticChecks { self.check(manual: false) }
                try? await Task.sleep(for: .seconds(6*3600))
            }
        }
    }
    func check(manual: Bool) {
        guard !checking, task == nil, !installing else { return }
        checking = true; error = nil
        task = Task { @MainActor in
            defer { checking = false; task = nil }
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/Davud77/BotPlus-PDF-Editor/releases/latest")!)
                request.timeoutInterval = 20; request.setValue("application/vnd.github+json",forHTTPHeaderField: "Accept"); request.setValue("BotPlusPDFEditor/"+installed,forHTTPHeaderField: "User-Agent")
                let (data,response) = try await URLSession.shared.data(for: request,delegate: UpdateTransferDelegate(api: true,progress: { _ in }))
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 2*1024*1024 else { throw URLError(.badServerResponse) }
                let candidate = try JSONDecoder().decode(ReleaseUpdate.self,from: data)
                guard !candidate.draft, !candidate.prerelease, candidate.pageURL != nil else { throw URLError(.cannotParseResponse) }
                if release?.tag_name != candidate.tag_name { clearStaging() }; release = candidate
                if policy.shouldNotify(version: candidate.tag_name,installed: installed) {
                    if !manual && notifiedVersion != candidate.tag_name { notifiedVersion = candidate.tag_name; onAvailable?() }
                    if automaticInstall { DispatchQueue.main.async { if self.automaticInstall && self.policy.shouldNotify(version: candidate.tag_name,installed: self.installed) { self.download() } } }
                }
            } catch is CancellationError { }
            catch { if Task.isCancelled { return }; self.error = "Не удалось проверить релиз. Проверьте сеть / Could not check release. Check your connection" }
        }
    }
    func skip() { guard let release else { return }; cancel(); clearStaging(); policy.skipped = release.tag_name; defaults.set(policy.skipped,forKey: "BotPlus.update.skipped") }
    func snooze() { cancel(); clearStaging(); policy.snoozedUntil = UpdatePolicy.month(after: Date()); defaults.set(policy.snoozedUntil,forKey: "BotPlus.update.snooze") }
    func resetSuppression() { notifiedVersion = nil; policy = UpdatePolicy(); defaults.removeObject(forKey: "BotPlus.update.skipped"); defaults.removeObject(forKey: "BotPlus.update.snooze") }
    func cancel() { task?.cancel() }
    private func clearStaging() {
        installationArmed = false
        if let staged { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent().deletingLastPathComponent()) }
        staged = nil
        if let lease { lease.stopAccessingSecurityScopedResource() }; lease = nil; folder = nil
    }
    func download() {
        guard task == nil, staged == nil, !installing, let release, ReleaseUpdate.isNewer(release.tag_name,than: installed), let asset = release.archive else { return }
        error = nil; progress = 0
        let transfer = UUID(); transferID = transfer
        task = Task { @MainActor in
            let directory = FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0].appendingPathComponent("BotPlusUpdates/"+UUID().uuidString,isDirectory: true)
            var completed = false
            defer { transferID = nil; progress = nil; task = nil; if !completed { try? FileManager.default.removeItem(at: directory) } }
            do {
                try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
                var expected = UpdateArchive.validDigest(asset.digest)
                if expected == nil {
                    guard let checksum = release.assets?.first(where: { $0.name == asset.name+".sha256" && $0.size <= 512 && ReleaseUpdate.assetURL($0.browser_download_url,tag: release.tag_name) }) else { throw UpdateFailure.invalid("Нет SHA-256 обновления / Missing update SHA-256") }
                    let (data,response) = try await URLSession.shared.data(for: URLRequest(url: checksum.browser_download_url),delegate: UpdateTransferDelegate(progress: { _ in }))
                    guard data.count <= 512, response.url.map(ReleaseUpdate.permittedDownload) == true, (response as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data,encoding: .utf8) else { throw URLError(.badServerResponse) }
                    let fields = text.split(whereSeparator: \.isWhitespace)
                    guard fields.count == 2, fields[1] == Substring(asset.name), let digest = UpdateArchive.validDigest("sha256:"+fields[0]) else { throw UpdateFailure.invalid("Неверная контрольная сумма / Invalid checksum") }; expected = digest
                }
                let delegate = UpdateTransferDelegate { value in Task { @MainActor in if self.transferID == transfer { self.progress = value } } }
                var request = URLRequest(url: asset.browser_download_url); request.timeoutInterval = 120
                let (url,response) = try await URLSession.shared.download(for: request,delegate: delegate)
                guard (response as? HTTPURLResponse)?.statusCode == 200, response.url.map(ReleaseUpdate.permittedDownload) == true else { throw URLError(.badServerResponse) }
                let archive = directory.appendingPathComponent("update.zip"); try FileManager.default.moveItem(at: url,to: archive)
                let version = release.version, current = Bundle.main.bundleURL, digest = expected!
                let worker = Task.detached(priority: .utility) {
                    let data = try Data(contentsOf: archive)
                    guard data.count == asset.size, UpdateArchive.checksum(data) == digest else { throw UpdateFailure.invalid("SHA-256 обновления не совпадает / Update SHA-256 mismatch") }
                    try Task.checkCancellation()
                    return try UpdateInstaller.unpack(archive: archive,directory: directory.appendingPathComponent("unpacked"),version: version,current: current)
                }
                let result = try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
                try Task.checkCancellation(); staged = result; completed = true
                if automaticInstall { armUsingBookmark() }
            } catch is CancellationError { }
            catch { if Task.isCancelled { return }; self.error = error.localizedDescription }
        }
    }
    func selectInstallFolder() {
        guard staged != nil, !installing else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.directoryURL = Bundle.main.bundleURL.deletingLastPathComponent()
        panel.message = "Выберите папку, где установлен BotPlus PDF Editor. Обновление установится при выходе / Select the installed app folder. Update will install on quit"
        panel.begin { [weak self] response in
            DispatchQueue.main.async {
                guard let self, response == .OK, let url = panel.url else { return }
                guard url.standardizedFileURL == Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL else { self.error = "Нужна папка текущего приложения / Select the current app folder"; return }
                do { self.defaults.set(try url.bookmarkData(options: .withSecurityScope,includingResourceValuesForKeys: nil,relativeTo: nil),forKey: "BotPlus.update.folder"); self.activate(url) }
                catch { self.error = error.localizedDescription }
            }
        }
    }
    func armUsingBookmark() {
        guard let data = defaults.data(forKey: "BotPlus.update.folder") else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,options: .withSecurityScope,relativeTo: nil,bookmarkDataIsStale: &stale), !stale else { return }
        activate(url)
    }
    private func activate(_ url: URL) {
        let current = Bundle.main.bundleURL
        guard url.standardizedFileURL == current.deletingLastPathComponent().standardizedFileURL else { return }
        guard !current.path.contains("/AppTranslocation/"), !current.path.hasPrefix("/Volumes/") else { error = "Сначала скопируйте приложение с DMG в папку установки / Copy the app from DMG to its installation folder first"; return }
        if let lease { lease.stopAccessingSecurityScopedResource() }
        if url.startAccessingSecurityScopedResource() { lease = url }
        folder = url; installationArmed = true
    }
    func disarm() { installationArmed = false }
    func installOnQuit() async throws {
        guard !installing, installationArmed, let staged, let folder, let release else { return }
        installing = true; defer { installing = false }
        let current = Bundle.main.bundleURL, version = release.version
        try await Task.detached(priority: .userInitiated) { try UpdateInstaller.install(staged: staged,current: current,folder: folder,version: version) }.value
        clearStaging()
    }
    func installationFailed(_ message: String) { error = message; installationArmed = false }
}
