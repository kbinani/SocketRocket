/**
 * NOTE: While publicly, SocketRocket does not support configuring the security policy with pinned certificates,
 * it is still possible to manually construct a security policy of this class. If you do this, note that you may
 * be open to MitM attacks, and we will not support any issues you may have. Dive at your own risk.
 */
@objc class SRPinningSecurityPolicy : SRSecurityPolicy {
    private let pinnedCertificates: [Any]
    
    init(withCertificates pinnedCertificates: [Any]) throws {
        guard !pinnedCertificates.isEmpty else {
            throw SRException(name: "Creating security policy failed.", reason: "Must specify at least one certificate when creating a pinning policy.")
        }
        
        self.pinnedCertificates = pinnedCertificates
        
        // Do not validate certificate chain since we're pinning to specific certificates.
        super.init(certificateChainValidationEnabled: false)
    }
    
    override func evaluateServerTrust(_ serverTrust: SecTrust, forDomain domain: String) -> Bool {
        swift_SRDebugLog("Pinned cert count: %d", self.pinnedCertificates.count);
        let requiredCertCount = self.pinnedCertificates.count
        
        var validatedCertCount = 0
        let serverCertCount: CFIndex = SecTrustGetCertificateCount(serverTrust)
        for i in 0 ..< serverCertCount {
            guard let cert = SecTrustGetCertificateAtIndex(serverTrust, i) else {
                continue
            }
            let data = SecCertificateCopyData(cert)
            for ref in self.pinnedCertificates {
                guard SecCertificateGetTypeID() == CFGetTypeID(ref as CFTypeRef) else {
                    continue
                }
                let trustedCert = ref as! SecCertificate
                // TODO: (nlutsenko) Add caching, so we don't copy the data for every pinned cert all the time.
                let trustedCertData = SecCertificateCopyData(trustedCert)
                if trustedCertData == data {
                    validatedCertCount += 1
                    break
                }
            }
        }
        return (requiredCertCount == validatedCertCount);
    }
}


struct SRException : Error {
    let name: String
    let reason: String
}
