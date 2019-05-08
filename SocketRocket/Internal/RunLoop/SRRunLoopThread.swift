@objc public class swift_SRRunLoopThread : Thread {
    private let _waitGroup: DispatchGroup
    private var _runLoop: RunLoop? = nil
    
    private static var _thread = { () -> swift_SRRunLoopThread in
        let thread = swift_SRRunLoopThread()
        thread.name = "com.facebook.SocketRocket.NetworkThread"
        thread.start()
        return thread
    }()
    
    @objc public static var sharedThread : swift_SRRunLoopThread {
        return _thread
    }
    
    @objc public override init() {
        _waitGroup = DispatchGroup()
        super.init()
        _waitGroup.enter()
    }
    
    @objc public override func main() {
        autoreleasepool { () in
            let runLoop = RunLoop.current
            _runLoop = runLoop
            _waitGroup.leave()
            
            // Add an empty run loop source to prevent runloop from spinning.
            var sourceCtx = CFRunLoopSourceContext(version: 0,
                                                   info: nil,
                                                   retain: nil,
                                                   release: nil,
                                                   copyDescription: nil,
                                                   equal: nil,
                                                   hash: nil,
                                                   schedule: nil,
                                                   cancel: nil,
                                                   perform: nil)
            repeat {
                let source = CFRunLoopSourceCreate(nil, 0, &sourceCtx)
                CFRunLoopAddSource(CFRunLoopGetCurrent(), source, CFRunLoopMode.defaultMode)
                // CFRelease(source)
            } while (false)
            
            while runLoop.run(mode: .default, before: .distantFuture) {
                
            }
            
            assert(false)
        }
    }
    
    @objc public var runLoop : RunLoop? {
        _ = _waitGroup.wait(timeout: DispatchTime.distantFuture)
        return _runLoop;
    }
}
