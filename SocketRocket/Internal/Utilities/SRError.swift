func swift_SRErrorWithDomainCodeDescription(_ domain: String, _ code: Int, _ description: String) -> NSError {
    return NSError(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey: description])
}

func swift_SRErrorWithCodeDescription(_ code: Int, _ description: String) -> NSError {
    return swift_SRErrorWithDomainCodeDescription(SRWebSocketErrorDomain, code, description)
}

func swift_SRErrorWithCodeDescriptionUnderlyingError(_ code: Int, _ description: String, _ underlyingError: NSError) -> NSError {
    return NSError(domain: SRWebSocketErrorDomain, code: code, userInfo: [NSLocalizedDescriptionKey: description, NSUnderlyingErrorKey: underlyingError])
}

func swift_SRHTTPErrorWithCodeDescription(_ httpCode: Int, _ errorCode: Int, _ description: String) -> NSError {
    return NSError(domain: SRWebSocketErrorDomain, code: errorCode, userInfo: [NSLocalizedDescriptionKey: description, SRHTTPResponseErrorKey: httpCode])
}
