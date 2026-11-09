import Foundation
import CryptoKit
import Darwin

let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/esai-wordbar/updates",isDirectory:true)
try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
let file = base.appendingPathComponent("ed25519.seed")
let key: Curve25519.Signing.PrivateKey
if FileManager.default.fileExists(atPath:file.path) {
    guard let seed = Data(base64Encoded:try String(contentsOf:file,encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines)) else { fatalError("Invalid update signing key") }
    key = try Curve25519.Signing.PrivateKey(rawRepresentation:seed)
} else {
    key = Curve25519.Signing.PrivateKey()
    let bytes = Data(key.rawRepresentation.base64EncodedString().utf8)
    let descriptor = open(file.path,O_WRONLY | O_CREAT | O_EXCL,0o600)
    guard descriptor >= 0 else { fatalError("Cannot create signing key") }
    let written = bytes.withUnsafeBytes { write(descriptor,$0.baseAddress,bytes.count) }
    close(descriptor)
    guard written == bytes.count else { fatalError("Cannot save signing key") }
}
try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
// Only the public key is printed. The private seed never enters the repository.
print(key.publicKey.rawRepresentation.base64EncodedString())
