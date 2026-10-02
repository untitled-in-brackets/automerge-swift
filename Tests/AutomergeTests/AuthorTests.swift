@testable import Automerge
import XCTest

class AuthorTests: XCTestCase {
    func testAuthorConstruction() {
        XCTAssertEqual(Author("alice").data, Data("alice".utf8))
        XCTAssertEqual(Author("alice").description, "616c696365")
        XCTAssertEqual(Author(data: Data([0xAB, 0xCD])).description, "abcd")

        let uuid = UUID(uuidString: "06a2b97e-69c9-4036-a97f-d4167a2bb779")!
        XCTAssertEqual(Author(uuid: uuid).description, "06a2b97e69c94036a97fd4167a2bb779")
    }

    func testDefaultDocumentHasNoAuthor() {
        let doc = Document()
        XCTAssertNil(doc.author)
        XCTAssertEqual(doc.authors, [])
        XCTAssertNil(doc.author(for: doc.actor))
    }

    func testChangesRecordAuthor() throws {
        let alice = Author("alice")
        let doc = Document(author: alice)
        XCTAssertEqual(doc.author, alice)

        try doc.put(obj: .ROOT, key: "greeting", value: .String("hello"))

        let hash = try XCTUnwrap(doc.heads().first)
        let change = try XCTUnwrap(doc.change(hash: hash))
        XCTAssertEqual(change.author, alice)
        XCTAssertEqual(doc.authors, [alice])
        XCTAssertEqual(doc.actors(for: alice), [change.actorId])
        XCTAssertEqual(doc.author(for: change.actorId), alice)
    }

    func testChangingAuthorRotatesActor() throws {
        let alice = Author("alice")
        let bob = Author("bob")
        let doc = Document(author: alice)
        try doc.put(obj: .ROOT, key: "a", value: .Int(1))
        let aliceActor = doc.actor

        doc.author = bob
        XCTAssertNotEqual(doc.actor, aliceActor)
        try doc.put(obj: .ROOT, key: "b", value: .Int(2))

        XCTAssertEqual(Set(doc.authors), [alice, bob])
        XCTAssertEqual(doc.actors(for: alice), [aliceActor])
        XCTAssertEqual(doc.actors(for: bob), [doc.actor])
        XCTAssertEqual(doc.author(for: aliceActor), alice)
        XCTAssertEqual(doc.author(for: doc.actor), bob)
    }

    func testAuthorsSurviveSaveLoadAndMerge() throws {
        let alice = Author("alice")
        let bob = Author("bob")

        let doc1 = Document(author: alice)
        try doc1.put(obj: .ROOT, key: "a", value: .Int(1))

        let doc2 = try Document(doc1.save(), author: bob)
        XCTAssertEqual(doc2.author, bob)
        XCTAssertEqual(doc2.authors, [alice])
        try doc2.put(obj: .ROOT, key: "b", value: .Int(2))

        try doc1.merge(other: doc2)
        XCTAssertEqual(Set(doc1.authors), [alice, bob])
        XCTAssertEqual(doc1.actors(for: alice), [doc1.actor])
        XCTAssertEqual(doc1.actors(for: bob), [doc2.actor])

        let changes = doc1.getHistory().compactMap { doc1.change(hash: $0) }
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes.map(\.author), [alice, bob])
        XCTAssertEqual(changes.map(\.actorId), [doc1.actor, doc2.actor])

        let doc2Changes = doc2.getHistory().compactMap { doc2.change(hash: $0) }
        XCTAssertEqual(doc2Changes.map(\.author), [alice, bob])
    }

    func testForkKeepsAuthorWithNewActor() throws {
        let alice = Author("alice")
        let doc = Document(author: alice)
        try doc.put(obj: .ROOT, key: "a", value: .Int(1))

        let fork = doc.fork()
        XCTAssertEqual(fork.author, alice)
        XCTAssertNotEqual(fork.actor, doc.actor)

        try fork.put(obj: .ROOT, key: "b", value: .Int(2))
        try doc.merge(other: fork)
        XCTAssertEqual(Set(doc.actors(for: alice)), [doc.actor, fork.actor])
    }
}
