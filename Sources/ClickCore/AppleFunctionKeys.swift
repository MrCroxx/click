/// Default top row on Apple keyboards with Spotlight, Dictation and Focus keys.
public enum AppleFunctionKeys {
    public static func mediaKey(for usage: UInt16) -> RawInputRouter.Key {
        let keys: [RawInputRouter.Key] = [
            .init(page: 12, usage: 0x70), .init(page: 12, usage: 0x6f),
            .init(page: 0xff01, usage: 0x10), .init(page: 0xff01, usage: 1),
            .init(page: 12, usage: 0xcf), .init(page: 1, usage: 0x9b),
            .init(page: 12, usage: 0xb4), .init(page: 12, usage: 0xcd),
            .init(page: 12, usage: 0xb3), .init(page: 12, usage: 0xe2),
            .init(page: 12, usage: 0xea), .init(page: 12, usage: 0xe9)
        ]
        precondition((58...69).contains(usage))
        return keys[Int(usage - 58)]
    }
}
