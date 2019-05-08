extension RunLoop {
    @objc(SR_networkRunLoop)
    public static func sr_network() -> RunLoop {
        return SRRunLoopThread.sharedThread.runLoop
    }
}
