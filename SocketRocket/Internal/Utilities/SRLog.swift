func swift_SRErrorLog(_ format: String, _ args: CVarArg...) {
    let formattedString = String(format: format, arguments: args)
    NSLog("[SocketRocket] %@", formattedString)
}


func swift_SRDebugLog(_ format: String, _ args: CVarArg...) {
    #if SR_DEBUG_LOG_ENABLED
    SRErrorLog(format, args)
    #endif
}
