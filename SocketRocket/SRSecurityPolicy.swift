@objc public class SRSecurityPolicy : NSObject {
    private let certificateChainValidationEnabled: Bool
    
    @objc(defaultPolicy)
    public static func `default`() -> SRSecurityPolicy {
        return SRSecurityPolicy()
    }
    
    @available(*, deprecated, message: "Using pinned certificates is neither secure nor supported in SocketRocket, and leads to security issues. Please use a proper, trust chain validated certificate.")
    @objc public static func pinnningPolicy(withCertificates pinnedCertificates: [Any]) -> SRSecurityPolicy {
        fatalError("Using pinned certificates is neither secure nor supported in SocketRocket, and leads to security issues. Please use a proper, trust chain validated certificate.")
    }
    
    @available(*, deprecated, message: "Disabling certificate chain validation is unsafe. Please use a proper Certificate Authority to issue your TLS certificates.")
    @objc public init(certificateChainValidationEnabled enabled: Bool) {
        self.certificateChainValidationEnabled = enabled
        super.init()
    }
    
    @objc public override init() {
        self.certificateChainValidationEnabled = true
        super.init()
    }
    
    @objc(updateSecurityOptionsInStream:)
    public func updateSecurityOptions(in stream: Stream) {
        // Enforce TLS 1.2
        stream.setProperty("kCFStreamSocketSecurityLevelTLSv1_2", forKey: kCFStreamPropertySocketSecurityLevel as Stream.PropertyKey)
        
        // Validate certificate chain for this stream if enabled.
        let sslOptions: [String: Any] = [
            kCFStreamSSLValidatesCertificateChain as String: NSNumber(value: self.certificateChainValidationEnabled)
        ]
        stream.setProperty(sslOptions, forKey: kCFStreamPropertySSLSettings as Stream.PropertyKey)
    }
    
    @objc public func evaluateServerTrust(_ serverTrust: SecTrust, forDomain domain: String) -> Bool {
        // No further evaluation happens in the default policy.
        return true
    }
}
