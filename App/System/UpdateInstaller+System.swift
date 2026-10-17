import AppSupportKit
import CoreKit
import CryptoKit
import Foundation
import Security
import UpdateKit

extension UpdateInstallError {
    var message: String {
        switch self {
        case .downloadFailed: String(localized: "update.error.download")
        case .mountFailed: String(localized: "update.error.mount")
        case .noApp: String(localized: "update.error.no_app")
        case .copyFailed: String(localized: "update.error.copy")
        case .invalidBundle: String(localized: "update.error.invalid_bundle")
        case .signatureFailed: String(localized: "update.error.signature")
        case .launchFailed: String(localized: "update.error.launch")
        }
    }
}

extension UpdateInstaller {
    static func system(runner: any ProcessRunner, token: @escaping @Sendable () -> String?) -> UpdateInstaller {
        let logFile = Paths.standard.updateLogFile
        let log = Log("Updater")
        return UpdateInstaller(
            runner: runner,
            token: token,
            download: { request, destination in
                try await AssetDownloader.download(request, to: destination)
            },
            spawn: { executable, arguments in
                try DetachedSpawn.spawn(executable, arguments: arguments, logFile: logFile)
            },
            signatureCheck: { staged in
                guard let requirement = AppSignature.requirement() else {
                    log.info("Skipping the signature check; the running app has no certificate.")
                    return nil
                }
                let valid = AppSignature.satisfies(staged, requirement: requirement)
                if !valid {
                    log.warning("The staged app does not satisfy the code-signing requirement.")
                }
                return valid
            }
        )
    }
}

enum AppSignature {
    static func requirement() -> SecRequirement? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
            SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
            SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess,
            let certificates = (information as? [String: Any])?[kSecCodeInfoCertificates as String]
                as? [SecCertificate],
            let leaf = certificates.first
        else {
            return nil
        }
        let digest = Insecure.SHA1.hash(data: SecCertificateCopyData(leaf) as Data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        var requirement: SecRequirement?
        let text = "identifier \"\(Bundle.main.bundleIdentifier ?? "")\" and certificate leaf = H\"\(hex)\""
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else {
            return nil
        }
        return requirement
    }

    static func satisfies(_ bundle: URL, requirement: SecRequirement) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            return false
        }
        return SecStaticCodeCheckValidity(staticCode, [], requirement) == errSecSuccess
    }
}
