import AutomergeUniffi

/// The unique internal identifier for an object stored in an Automerge document.
public struct ObjId: Hashable, Sendable {
    var bytes: [UInt8]
    /// The root identifier for an Automerge document.
    public static let ROOT = ObjId(bytes: AutomergeUniffi.root())

    public static func == (lhs: ObjId, rhs: ObjId) -> Bool {
        lhs.identity == rhs.identity
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identity.actor)
        hasher.combine(identity.counter)
    }

    // wire layout from automerge's exid.rs: tag | actor len | actor | actor index | counter.
    // the actor index is doc-local and shifts after merges, so the core excludes it from equality.
    private var identity: (actor: ArraySlice<UInt8>, counter: UInt64?) {
        guard let tag = bytes.first, tag >> 4 == 1 else { return (bytes[...], nil) }
        var index = 1
        guard let actorLength = readULEB128(at: &index) else { return (bytes[...], nil) }
        index += Int(actorLength)
        guard index <= bytes.count else { return (bytes[...], nil) }
        let actor = bytes[..<index]
        guard readULEB128(at: &index) != nil, let counter = readULEB128(at: &index) else {
            return (bytes[...], nil)
        }
        return (actor, counter)
    }

    private func readULEB128(at index: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift >= 64 { return nil }
        }
        return nil
    }
}

extension ObjId: CustomDebugStringConvertible {
    public var debugDescription: String {
        if bytes == AutomergeUniffi.root() {
            return "ObjId.ROOT"
        } else {
            return "ObjId(\(bytes.map { Swift.String(format: "%02hhx", $0) }.joined()))"
        }
    }
}
