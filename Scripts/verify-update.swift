import Foundation
import CryptoKit

guard CommandLine.arguments.count == 4,
      let publicKey = Data(base64Encoded:CommandLine.arguments[1]),
      let signature = Data(base64Encoded:CommandLine.arguments[3]) else {
    fputs("Usage: verify-update <public-key-base64> <archive> <signature-base64>\n",stderr)
    exit(2)
}
let key = try Curve25519.Signing.PublicKey(rawRepresentation:publicKey)
let bytes = try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]),options:.mappedIfSafe)
guard key.isValidSignature(signature,for:bytes) else {
    fputs("Update signature does not match the app's pinned public key\n",stderr)
    exit(1)
}
print("Update signature verified against the app's public key")
