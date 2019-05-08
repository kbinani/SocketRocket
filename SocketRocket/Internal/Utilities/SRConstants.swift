private let pagesize: Int = { Int(getpagesize()) }()

func swift_SRDefaultBufferSize() -> Int {
    return pagesize
}
