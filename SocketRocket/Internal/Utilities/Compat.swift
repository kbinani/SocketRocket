private func compat_SRSecurityPolicy() {
    do {
        SRSecurityPolicy.init()
        SRSecurityPolicy.init(certificateChainValidationEnabled: true)
        let policy = SRSecurityPolicy.default()
        SRSecurityPolicy.pinnningPolicy(withCertificates: [])
        let stream = InputStream(fileAtPath: "")!
        policy.updateSecurityOptions(in: stream)
        var trust: SecTrust? = nil
        let certs = [AnyObject]()
        SecTrustCreateWithCertificates(certs as! CFArray, nil, &trust)
        policy.evaluateServerTrust(trust!, forDomain: "")
    }
}
