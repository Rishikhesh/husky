import Foundation
import Security

/// The dmg install's one-click update: download the release's dmg, check the
/// app inside is signed by the same certificate as this one and says the
/// version asked for, and put it where this app is. A restart runs it.
///
/// The signature check is the whole point: the download is only trusted
/// because it satisfies this running app's own designated requirement, so
/// nothing but a build signed with the release certificate replaces it.
enum DMGUpdate {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func downloadURL(version: String) -> URL {
        URL(string: "https://github.com/Rishikhesh/husky/releases/download/"
            + "v\(version)/Husky-\(version).dmg")!
    }

    static func install(
        version: String,
        replacing app: URL = Bundle.main.bundleURL,
        runner: any CommandRunner = ProcessRunner()
    ) async throws {
        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory
            .appending(path: "husky-update-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: work) }

        let (downloaded, response) = try await URLSession.shared.download(
            from: downloadURL(version: version)
        )
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw Failure(description: "download answered \(status)")
        }
        let dmg = work.appending(path: "Husky.dmg")
        try fileManager.moveItem(at: downloaded, to: dmg)

        // staged on the app's own volume, so the swap is a rename and the
        // old app is never half-replaced.
        let stageFolder = try fileManager.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: app, create: true
        )
        defer { try? fileManager.removeItem(at: stageFolder) }
        let staged = stageFolder.appending(path: app.lastPathComponent, directoryHint: .isDirectory)
        let mount = work.appending(path: "mount", directoryHint: .isDirectory)
        try await run(runner, "/usr/bin/hdiutil", [
            "attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path,
        ])
        let detach = command("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
        do {
            try await run(runner, "/usr/bin/ditto", [
                mount.appending(path: "Husky.app").path, staged.path,
            ])
        } catch {
            _ = await runner.run(detach)
            throw error
        }
        _ = await runner.run(detach)

        try verify(staged, version: version)
        _ = try fileManager.replaceItemAt(app, withItemAt: staged)
    }

    /// the new app must say `version` and satisfy this app's designated
    /// requirement: same bundle id, same signing certificate.
    static func verify(
        _ app: URL,
        version: String,
        requirement: SecRequirement? = ownRequirement()
    ) throws {
        let found = UpdateCheck.installedVersion(atBundle: app)
        guard found == version else {
            throw Failure(description: "the dmg holds \(found ?? "no version"), not \(version)")
        }
        guard let requirement else {
            throw Failure(description: "this build has no designated requirement to check against")
        }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else {
            throw Failure(description: "the new app has no readable signature")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidity(code, flags, requirement)
        guard status == errSecSuccess else {
            throw Failure(description: "the new app's signature doesn't match this one (\(status))")
        }
    }

    static func ownRequirement() -> SecRequirement? {
        var me: SecCode?
        var onDisk: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &onDisk) == errSecSuccess, let onDisk,
              SecCodeCopyDesignatedRequirement(onDisk, [], &requirement) == errSecSuccess
        else { return nil }
        return requirement
    }

    private static func command(_ path: String, _ arguments: [String]) -> Command {
        Command(
            executable: URL(fileURLWithPath: path),
            arguments: arguments,
            environment: [:],
            timeout: 120
        )
    }

    private static func run(_ runner: any CommandRunner, _ path: String, _ arguments: [String]) async throws {
        let result = await runner.run(command(path, arguments))
        guard result.ending == .exited(0) else {
            let name = URL(fileURLWithPath: path).lastPathComponent
            throw Failure(description: "\(name) \(arguments.first ?? "") failed: "
                + (BrewUpgrade.reason(inStderr: result.stderr) ?? "\(result.ending)"))
        }
    }
}
