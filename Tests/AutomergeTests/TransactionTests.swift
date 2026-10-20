import Automerge
import XCTest

class TransactionTests: XCTestCase {
    func testTransactCommitsEditsAsOneChange() throws {
        let doc = Document()
        try doc.put(obj: .ROOT, key: "title", value: .String("Groceries"))
        XCTAssertEqual(doc.getHistory().count, 1)

        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let todo = try doc.transact(message: "Add a todo", timestamp: timestamp) { doc in
            let todos = try doc.putObject(obj: .ROOT, key: "todos", ty: .List)
            let todo = try doc.insertObject(obj: todos, index: 0, ty: .Map)
            try doc.put(obj: todo, key: "title", value: .String("Buy milk"))
            try doc.put(obj: todo, key: "done", value: .Boolean(false))
            return todo
        }

        let history = doc.getHistory()
        XCTAssertEqual(history.count, 2)
        let change = try XCTUnwrap(doc.change(hash: history[1]))
        XCTAssertEqual(change.message, "Add a todo")
        XCTAssertEqual(change.timestamp, timestamp)
        XCTAssertEqual(try doc.get(obj: todo, key: "title"), .Scalar(.String("Buy milk")))
        XCTAssertEqual(try doc.get(obj: todo, key: "done"), .Scalar(.Boolean(false)))
    }

    func testTransactWithoutEditsCreatesNoChange() throws {
        let doc = Document()
        try doc.put(obj: .ROOT, key: "a", value: .Int(1))
        let heads = doc.heads()

        try doc.transact(message: "nothing to see") { doc in
            XCTAssertEqual(try doc.get(obj: .ROOT, key: "a"), .Scalar(.Int(1)))
        }

        XCTAssertEqual(doc.heads(), heads)
        XCTAssertEqual(doc.getHistory().count, 1)
    }

    func testTransactCommitsPendingEditsSeparately() throws {
        let doc = Document()
        // Pending, not yet committed, when the transaction starts.
        try doc.put(obj: .ROOT, key: "before", value: .Int(1))

        try doc.transact(message: "transaction") { doc in
            try doc.put(obj: .ROOT, key: "inside", value: .Int(2))
        }

        let history = doc.getHistory()
        XCTAssertEqual(history.count, 2)
        let pending = try XCTUnwrap(doc.change(hash: history[0]))
        let transaction = try XCTUnwrap(doc.change(hash: history[1]))
        XCTAssertNil(pending.message)
        XCTAssertEqual(transaction.message, "transaction")
        // The first change holds only the edit from before the transaction.
        XCTAssertEqual(try doc.getAt(obj: .ROOT, key: "before", heads: [history[0]]), .Scalar(.Int(1)))
        XCTAssertNil(try doc.getAt(obj: .ROOT, key: "inside", heads: [history[0]]))
    }

    func testTransactRollsBackOnError() throws {
        struct Failure: Error {}
        let doc = Document()
        try doc.put(obj: .ROOT, key: "kept", value: .Int(1))
        doc.commitWith(message: "first")
        try doc.put(obj: .ROOT, key: "pending", value: .Int(2))

        do {
            try doc.transact(message: "fails") { doc in
                try doc.put(obj: .ROOT, key: "discarded", value: .Int(3))
                try doc.put(obj: .ROOT, key: "kept", value: .Int(99))
                throw Failure()
            }
            XCTFail("transact should rethrow the error from its body")
        } catch is Failure {}

        XCTAssertEqual(try doc.get(obj: .ROOT, key: "kept"), .Scalar(.Int(1)))
        XCTAssertNil(try doc.get(obj: .ROOT, key: "discarded"))
        // Edits pending from before the transaction were committed first, not rolled back with it.
        XCTAssertEqual(try doc.get(obj: .ROOT, key: "pending"), .Scalar(.Int(2)))
        let history = doc.getHistory()
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.compactMap { doc.change(hash: $0)?.message }, ["first"])
        XCTAssertEqual(doc.rollback(), 0)
    }

    func testRollbackDiscardsPendingEdits() throws {
        let doc = Document()
        try doc.put(obj: .ROOT, key: "committed", value: .Int(1))
        doc.commitWith(message: "first")

        try doc.put(obj: .ROOT, key: "a", value: .Int(2))
        try doc.put(obj: .ROOT, key: "committed", value: .Int(3))
        XCTAssertEqual(doc.rollback(), 2)

        XCTAssertNil(try doc.get(obj: .ROOT, key: "a"))
        XCTAssertEqual(try doc.get(obj: .ROOT, key: "committed"), .Scalar(.Int(1)))
        XCTAssertEqual(doc.getHistory().count, 1)
        XCTAssertEqual(doc.rollback(), 0)
    }

    func testRollbackOnFreshDocumentLeavesNoHistory() throws {
        let doc = Document()
        try doc.put(obj: .ROOT, key: "a", value: .Int(1))
        XCTAssertEqual(doc.rollback(), 1)
        XCTAssertEqual(doc.getHistory(), [])
        XCTAssertEqual(doc.keys(obj: .ROOT), [])

        try doc.put(obj: .ROOT, key: "b", value: .Int(2))
        let loaded = try Document(doc.save())
        XCTAssertEqual(loaded.getHistory().count, 1)
        XCTAssertEqual(try loaded.get(obj: .ROOT, key: "b"), .Scalar(.Int(2)))
    }

    func testTransactIsNotSplitByConcurrentCommits() throws {
        final class Observed: @unchecked Sendable {
            var heads: Set<ChangeHash> = []
            var saved = Data()
            var historyCount = 0
        }

        let doc = Document()
        try doc.put(obj: .ROOT, key: "setup", value: .Int(0))
        let historyBefore = doc.getHistory()

        let inTransaction = DispatchSemaphore(value: 0)
        let observed = Observed()
        let group = DispatchGroup()
        DispatchQueue.global().async(group: group) {
            inTransaction.wait()
            // On an unlocked document each of these would commit whatever is pending.
            observed.heads = doc.heads()
            observed.saved = doc.save()
            observed.historyCount = doc.getHistory().count
        }

        try doc.transact(message: "batch") { doc in
            try doc.put(obj: .ROOT, key: "a", value: .Int(1))
            inTransaction.signal()
            // Give the other thread time to call into the document while the transaction is open.
            // It has to wait for the commit, so the batch still lands as one change.
            Thread.sleep(forTimeInterval: 0.2)
            try doc.put(obj: .ROOT, key: "b", value: .Int(2))
            try doc.put(obj: .ROOT, key: "c", value: .Int(3))
        }
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)

        let history = doc.getHistory()
        XCTAssertEqual(history.count, historyBefore.count + 1)
        let batch = try XCTUnwrap(doc.change(hash: try XCTUnwrap(history.last)))
        XCTAssertEqual(batch.message, "batch")
        // The other thread only saw the document once the whole transaction was committed.
        XCTAssertEqual(observed.heads, doc.heads())
        XCTAssertEqual(observed.historyCount, history.count)
        let loaded = try Document(observed.saved)
        XCTAssertEqual(try loaded.get(obj: .ROOT, key: "c"), .Scalar(.Int(3)))
    }

    #if canImport(Combine)
    func testTransactPublishesOneUpdate() throws {
        struct Failure: Error {}
        let doc = Document()
        var willChangeCount = 0
        var didChangeCount = 0
        var headsAtDidChange: Set<ChangeHash> = []
        let willChangeHandle = doc.objectWillChange.sink { willChangeCount += 1 }
        let didChangeHandle = doc.objectDidChange.sink {
            didChangeCount += 1
            // Reading the heads here is what the objectDidChange documentation suggests; it
            // commits the pending change, which must not split the transaction.
            headsAtDidChange = doc.heads()
        }

        try doc.transact(message: "batch") { doc in
            try doc.put(obj: .ROOT, key: "a", value: .Int(1))
            try doc.put(obj: .ROOT, key: "b", value: .Int(2))
            try doc.put(obj: .ROOT, key: "c", value: .Int(3))
        }
        XCTAssertEqual(willChangeCount, 1)
        XCTAssertEqual(didChangeCount, 1)
        XCTAssertEqual(headsAtDidChange, doc.heads())
        XCTAssertEqual(doc.getHistory().count, 1)

        XCTAssertThrowsError(
            try doc.transact { doc in
                try doc.put(obj: .ROOT, key: "d", value: .Int(4))
                throw Failure()
            }
        )
        XCTAssertEqual(willChangeCount, 2)
        XCTAssertEqual(didChangeCount, 2)
        XCTAssertEqual(doc.getHistory().count, 1)

        withExtendedLifetime((willChangeHandle, didChangeHandle)) {}
    }
    #endif
}
