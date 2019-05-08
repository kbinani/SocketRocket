typealias swift_SRProxyConnectCompletion = (_ error: Error?, _ readStream: InputStream?, _ writeStream: OutputStream?) -> Void


@objc public class swift_SRProxyConnect : NSObject, StreamDelegate {
    private let url: URL
    private var inputStream: InputStream? = nil
    private var outputStream: OutputStream? = nil

    private var _completion: swift_SRProxyConnectCompletion? = nil

    private var _httpProxyHost: String? = nil
    private var _httpProxyPort: UInt32? = nil

    private var _receivedHTTPHeaders: CFHTTPMessage? = nil

    private var _socksProxyHost: String? = nil
    private var _socksProxyPort: UInt32? = nil;
    private var _socksProxyUsername: String? = nil
    private var _socksProxyPassword: String? = nil

    private var _connectionRequiresSSL: Bool = false

    private var _inputQueue: [Data] = []
    private let _writeQueue: DispatchQueue

    //MARK: - Init

    @objc public init(withURL url: URL) {
        self.url = url
        self._connectionRequiresSSL = swift_SRURLRequiresSSL(url)

        self._writeQueue = DispatchQueue(label: "com.facebook.socketrocket.proxyconnect.write")
        self._inputQueue.reserveCapacity(2)

        super.init()
    }

    deinit {
        // If we get deallocated before the socket open finishes - we need to cleanup everything.

        if let inputStream = self.inputStream {
            self.inputStream = nil
            inputStream.remove(from: RunLoop.sr_network(), forMode: .default)
            inputStream.delegate = nil
            inputStream.close()
        }

        if let outputStream = self.outputStream {
            self.outputStream = nil
            outputStream.delegate = nil
            outputStream.close()
        }
    }

    //MARK: - Open

    func openNetworkStream(with completion: @escaping swift_SRProxyConnectCompletion) {
        self._completion = completion
        self._configureProxy()
    }

    //MARK: - Flow

    private func _didConnect() {
        swift_SRDebugLog("_didConnect, return streams")
        if _connectionRequiresSSL {
            if let httpProxyHost = _httpProxyHost {
                // Must set the real peer name before turning on SSL
                swift_SRDebugLog("proxy set peer name to real host %@", self.url.host ?? "")
                self.outputStream?.setProperty(self.url.host, forKey: .init("_kCFStreamPropertySocketPeerName"))
            }
        }
        self._receivedHTTPHeaders = nil

        let inputStream = self.inputStream
        let outputStream = self.outputStream
        
        self.inputStream = nil;
        self.outputStream = nil;

        inputStream?.remove(from: RunLoop.sr_network(), forMode: .default)
        inputStream?.delegate = nil
        outputStream?.delegate = nil

        self._completion?(nil, inputStream, outputStream)
    }

    private func _failWithError(_ e: Error?) {
        swift_SRDebugLog("_failWithError, return error")
        var error: Error
        if let e = e {
            error = e
        } else {
            error = swift_SRHTTPErrorWithCodeDescription(500, 2132, "Proxy Error")
        }

        self._receivedHTTPHeaders = nil

        self.inputStream?.delegate = nil;
        self.outputStream?.delegate = nil;

        self.inputStream?.remove(from: RunLoop.sr_network(), forMode: .default)
        self.inputStream?.close()
        self.outputStream?.close()
        self.inputStream = nil;
        self.outputStream = nil;
        self._completion?(error, nil, nil)
    }

    // get proxy setting from device setting
    private func _configureProxy() {
        swift_SRDebugLog("configureProxy")
        
        guard let host = self.url.host, let proxySettings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [AnyHashable: Any] else {
            self._openConnection()
            return
        }

        // CFNetworkCopyProxiesForURL doesn't understand ws:// or wss://
        guard let httpURL = { () -> URL? in
            if self._connectionRequiresSSL {
                return URL(string: String(format: "https://%@", host))
            } else {
                return URL(string: String(format: "http://%@", host))
            }
        }() else {
            self._openConnection()
            return
        }

        guard let proxies = CFNetworkCopyProxiesForURL(httpURL as CFURL, proxySettings as CFDictionary).takeRetainedValue() as? [Any] else {
            return
        }
        guard !proxies.isEmpty else {
            swift_SRDebugLog("configureProxy no proxies")
            self._openConnection()
            return                 // no proxy
        }
        guard let settings = proxies.first as? [AnyHashable: Any] else {
            self._openConnection()
            return
        }
        guard let proxyType = settings[kCFProxyTypeKey] as? String else {
            self._openConnection()
            return
        }
        if proxyType == kCFProxyTypeAutoConfigurationURL as String {
            if let pacURL = settings[kCFProxyAutoConfigurationURLKey as String] as? URL {
                self._fetchPAC(pacURL, withProxySettings: proxySettings)
                return
            }
        }
        if proxyType == kCFProxyTypeAutoConfigurationJavaScript as String {
            if let script = settings[kCFProxyAutoConfigurationJavaScriptKey as String] as? String {
                self._runPACScript(script, withProxySettings: proxySettings)
                return
            }
        }
        self._readProxySettingWithType(proxyType, settings: settings)
        self._openConnection()
    }

    private func _readProxySettingWithType(_ proxyType: String, settings: [AnyHashable: Any]) {
        if proxyType == kCFProxyTypeHTTP as String || proxyType == kCFProxyTypeHTTPS as String {
            self._httpProxyHost = settings[kCFProxyHostNameKey as String] as? String
            if let portValue = settings[kCFProxyPortNumberKey as String] as? NSNumber {
                self._httpProxyPort = portValue.uint32Value
            }
        }
        
        if proxyType == kCFProxyTypeSOCKS as String {
            self._socksProxyHost = settings[kCFProxyHostNameKey as String] as? String
            if let portValue = settings[kCFProxyPortNumberKey as String] as? NSNumber {
                self._socksProxyPort = portValue.uint32Value
            }
            self._socksProxyUsername = settings[kCFProxyUsernameKey as String] as? String
            self._socksProxyPassword = settings[kCFProxyPasswordKey as String] as? String
        }
        if _httpProxyHost != nil {
            swift_SRDebugLog("Using http proxy %@:%u", self._httpProxyHost ?? "", _httpProxyPort ?? 0)
        } else if _socksProxyHost != nil {
            swift_SRDebugLog("Using socks proxy %@:%u", _socksProxyHost ?? "", _socksProxyPort ?? 0)
        } else {
            swift_SRDebugLog("configureProxy no proxies")
        }
    }

    private func _fetchPAC(_ PACurl: URL, withProxySettings proxySettings: [AnyHashable: Any]) {
        swift_SRDebugLog("SRWebSocket fetchPAC:%@", PACurl as NSURL)

        if PACurl.isFileURL {
            if let script = try? String(contentsOf: PACurl) {
                self._runPACScript(script, withProxySettings: proxySettings)
            } else {
                self._openConnection()
            }
            return
        }

        let scheme = PACurl.scheme?.lowercased()
        if scheme != "http" && scheme != "https" {
            // Don't know how to read data from this URL, we'll have to give up
            // We'll simply assume no proxies, and start the request as normal
            self._openConnection()
            return
        }
        let request = URLRequest(url: PACurl)
        let session = URLSession.shared
        let task = session.dataTask(with: request) { [weak self] (data, response, error) in
            if error == nil, let data = data, let script = String(data: data, encoding: .utf8) {
                self?._runPACScript(script, withProxySettings: proxySettings)
            } else {
                self?._openConnection()
            }
        }
        task.resume()
    }

    private func _runPACScript(_ script: String, withProxySettings proxySettings: [AnyHashable: Any]) {
        swift_SRDebugLog("runPACScript")
        // From: http://developer.apple.com/samplecode/CFProxySupportTool/listing1.html
        // Work around <rdar://problem/5530166>.  This dummy call to
        // CFNetworkCopyProxiesForURL initialise some state within CFNetwork
        // that is required by CFNetworkCopyProxiesForAutoConfigurationScript.
        _ = CFNetworkCopyProxiesForURL(url as CFURL, proxySettings as CFDictionary).takeRetainedValue()

        // Obtain the list of proxies by running the autoconfiguration script
        var err: Unmanaged<CFError>? = nil

        // CFNetworkCopyProxiesForAutoConfigurationScript doesn't understand ws:// or wss://
        guard let host = self.url.host, let httpURL = { () -> URL? in
            if _connectionRequiresSSL {
                return URL(string: String(format: "https://%@", host))
            } else {
                return URL(string: String(format: "http://%@", host))
            }
        }() else {
            self._openConnection()
            return
        }

        guard let proxies = CFNetworkCopyProxiesForAutoConfigurationScript(script as CFString, httpURL as CFURL, &err)?.takeRetainedValue() as? [Any] else {
            self._openConnection()
            return
        }
        if err == nil, !proxies.isEmpty, let settings = proxies.first as? [AnyHashable: Any], let proxyType = settings[kCFProxyTypeKey as String] as? String {
            self._readProxySettingWithType(proxyType, settings: settings)
        }
        self._openConnection()
    }

    private func _openConnection() {
        self._initializeStreams()

        self.inputStream?.schedule(in: RunLoop.sr_network(), forMode: .default)
        //[self.outputStream scheduleInRunLoop:[NSRunLoop SR_networkRunLoop]
        //                           forMode:NSDefaultRunLoopMode];
        self.outputStream?.open()
        self.inputStream?.open()
    }

    private func _initializeStreams() {
        assert((self.url.port ?? 0) <= UInt32.max)
        var port: UInt32 = UInt32(self.url.port ?? 0)
        if port == 0 {
            port = self._connectionRequiresSSL ? 443 : 80
        }
        var host = self.url.host ?? ""

        if let httpProxyHost = self._httpProxyHost {
            host = httpProxyHost
            port = _httpProxyPort ?? 80
        }

        var readStream: Unmanaged<CFReadStream>? = nil
        var writeStream: Unmanaged<CFWriteStream>? = nil

        swift_SRDebugLog("ProxyConnect connect stream to %@:%u", host, port)
        CFStreamCreatePairWithSocketToHost(nil, host as CFString, port, &readStream, &writeStream)

        self.outputStream = writeStream?.takeRetainedValue()
        self.inputStream = readStream?.takeRetainedValue()

        if let socksProxyHost = self._socksProxyHost {
            swift_SRDebugLog("ProxyConnect set sock property stream to %@:%u user %@ password %@", _socksProxyHost ?? "", _socksProxyPort ?? 0, _socksProxyUsername ?? "", _socksProxyPassword ?? "")
            var settings: [AnyHashable: Any] = [:]
            settings.reserveCapacity(4)
            settings[StreamSOCKSProxyConfiguration.hostKey] = socksProxyHost
            if let socksProxyPort = self._socksProxyPort {
                settings[StreamSOCKSProxyConfiguration.portKey] = NSNumber(value: socksProxyPort)
            }
            if let socksProxyUsername = self._socksProxyUsername {
                settings[StreamSOCKSProxyConfiguration.userKey] = socksProxyUsername
            }
            if let socksProxyPassword = self._socksProxyPassword {
                settings[StreamSOCKSProxyConfiguration.passwordKey] = socksProxyPassword
            }
            self.inputStream?.setProperty(settings, forKey: Stream.PropertyKey.socksProxyConfigurationKey)
            self.outputStream?.setProperty(settings, forKey: Stream.PropertyKey.socksProxyConfigurationKey)
        }
        self.inputStream?.delegate = self;
        self.outputStream?.delegate = self;
    }

    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        swift_SRDebugLog("stream handleEvent %u", eventCode.rawValue)
        switch eventCode {
        case Stream.Event.openCompleted:
            if aStream === self.inputStream {
                if _httpProxyHost != nil {
                    self._proxyDidConnect()
                } else {
                    self._didConnect()
                }
            }
        case Stream.Event.errorOccurred:
            self._failWithError(aStream.streamError)
        case Stream.Event.endEncountered:
            self._failWithError(aStream.streamError)
        case Stream.Event.hasBytesAvailable:
            if aStream === self.inputStream {
                self._processInputStream()
            }
        case Stream.Event.hasSpaceAvailable:
            swift_SRDebugLog("hasSpaceAvailable  %@", aStream)
        default:
            swift_SRDebugLog("(default)  %@", aStream)
        }
    }

    private func _proxyDidConnect() {
        swift_SRDebugLog("Proxy Connected")
        var port: UInt32 = UInt32(self.url.port ?? 0)
        if (port == 0) {
            port = self._connectionRequiresSSL ? 443 : 80
        }
        // Send HTTP CONNECT Request
        let connectRequestStr = String(format: "CONNECT %@:%u HTTP/1.1\r\nHost: %@\r\nConnection: keep-alive\r\nProxy-Connection: keep-alive\r\n\r\n", self.url.host ?? "", port, self.url.host ?? "")

        swift_SRDebugLog("Proxy sending %@", connectRequestStr)

        if let message = connectRequestStr.data(using: .utf8) { //TODO: handle error here
            self._writeData(message)
        }
    }

    // handles the incoming bytes and sending them to the proper processing method
    private func _processInputStream() {
        let size = swift_SRDefaultBufferSize()
        var buf = Data(capacity: size)
        let length = buf.withContiguousMutableStorageIfAvailable { (buffer) -> Int in
            guard let inputStream = self.inputStream else {
                return 0
            }
            guard let address: UnsafeMutablePointer<UInt8> = buffer.baseAddress else {
                return 0
            }
            let length = inputStream.read(address, maxLength: size)
            return length
        } ?? 0
        
        guard length > 0 else {
            return
        }
        
        let process = self._inputQueue.isEmpty
        
        let data = buf.subdata(in: 0 ..< length)
        self._inputQueue.append(data)
        
        if process {
            self._dequeueInput()
        }
    }

    // dequeue the incoming input so it is processed in order
    private func _dequeueInput() {
        while !_inputQueue.isEmpty {
            let data = self._inputQueue.removeFirst()
            
            // No need to process any data further, we got the full header data.
            if self._proxyProcessHTTPResponseWithData(data) {
                break
            }
        }
    }

    //handle checking the proxy  connection status
    private func _proxyProcessHTTPResponseWithData(_ data: Data) -> Bool {
        let headers: CFHTTPMessage
        if let receivedHeaders = self._receivedHTTPHeaders {
            headers = receivedHeaders
        } else {
            headers = CFHTTPMessageCreateEmpty(nil, false).takeRetainedValue()
            self._receivedHTTPHeaders = headers
        }
        
        data.withContiguousStorageIfAvailable { (bytes) in
            guard let address = bytes.baseAddress else {
                return
            }
            CFHTTPMessageAppendBytes(headers, address, data.count)
        }
        if CFHTTPMessageIsHeaderComplete(headers) {
            swift_SRDebugLog("Finished reading headers %@", CFHTTPMessageCopyAllHeaderFields(headers)?.takeRetainedValue() as? [AnyHashable: Any] ?? [:])
            self._proxyHTTPHeadersDidFinish()
            return true
        }

        return false
    }

    private func _proxyHTTPHeadersDidFinish() {
        guard let headers = self._receivedHTTPHeaders else {
            return
        }
        let responseCode = CFHTTPMessageGetResponseStatusCode(headers)

        if responseCode >= 299 {
            swift_SRDebugLog("Connect to Proxy Request failed with response code %d", responseCode)
            let error = swift_SRHTTPErrorWithCodeDescription(responseCode, 2132,
                                                             String(format: "Received bad response code from proxy server: %d.", responseCode))
            self._failWithError(error)
            return
        }
        swift_SRDebugLog("proxy connect return %d, call socket connect", responseCode)
        self._didConnect()
    }

    private static let SRProxyConnectWriteTimeout: TimeInterval = 5

    private func _writeData(_ data: Data) {
        self._writeQueue.async { [weak self] in
            guard let myself = self else {
                return
            }
            guard let outputStream = myself.outputStream else {
                return
            }
            var timeout = Int(swift_SRProxyConnect.SRProxyConnectWriteTimeout * 1000000) // wait timeout before giving up
            while outputStream.hasSpaceAvailable {
                usleep(100) //wait until the socket is ready
                timeout -= 100
                if timeout < 0 {
                    let error = swift_SRHTTPErrorWithCodeDescription(408, 2132, "Proxy timeout")
                    myself._failWithError(error)
                } else if let streamError = outputStream.streamError {
                    myself._failWithError(streamError)
                }
            }
            data.withContiguousStorageIfAvailable({ (buffer) in
                guard let address = buffer.baseAddress else {
                    return
                }
                outputStream.write(address, maxLength: data.count)
            })
        }
    }
}
