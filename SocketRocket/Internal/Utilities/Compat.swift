private func compat_SRSecurityPolicy() {
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

private func compat_NSRunLoop() {
    let runLoop: RunLoop = RunLoop.sr_network()
}
