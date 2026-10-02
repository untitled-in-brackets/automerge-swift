import AutomergeUniffi
import Foundation

/// An opaque identifier for who made a change to an Automerge document.
///
/// Unlike ``ActorId``, which identifies a single document instance and must be unique per concurrent
/// editor, an `Author` is a stable identity for a person or agent. Set ``Document/author`` and Automerge
/// records it on every subsequent ``Change``; one author may map to many actors over time.
public struct Author: Equatable, Hashable, Sendable {
    public let data: Data

    init(ffi: AutomergeUniffi.Author) {
        data = Data(ffi)
    }

    /// Creates an author from the bytes you provide.
    public init(data: Data) {
        self.data = data
    }

    /// Creates an author from the UTF-8 bytes of a string, such as a user identifier.
    public init(_ string: String) {
        data = Data(string.utf8)
    }

    /// Creates an author from the contents of a UUID.
    public init(uuid: UUID) {
        data = withUnsafeBytes(of: uuid.uuid) { Data($0) }
    }

    var ffi: AutomergeUniffi.Author {
        [UInt8](data)
    }
}

extension Author: CustomStringConvertible {
    /// A hex-encoded string that represents the bytes of the author.
    public var description: String {
        data.map { String(format: "%02hhx", $0) }.joined()
    }
}
