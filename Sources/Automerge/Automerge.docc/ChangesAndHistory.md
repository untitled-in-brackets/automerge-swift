# Tracking Changes and History

Track, inspect, and synchronize the changes within Automerge documents.

## Overview

An Automerge document is a little like a git repository in that it is composed of a graph of changes, each identified by a hash. 
Like a git repository, a point in the history of an Automerge document can be referenced by its hash. 
_Unlike_ a git repository, an Automerge document can have multiple heads for a given point in time, representing a merge of concurrent changes. 

### Heads and change hashes

From time to time you may want to refer to a particular point in the document history. 
For example, you may want to read values at a past point in time, or get the changes since that time.
Use ``Document/heads()`` to obtain the current heads of the document, which returns a set of ``ChangeHash``.
The set of `ChangeHash` that Automerge returns represent a discrete point in time for an Automerge document.
`Document` includes families of methods that accept `[ChangeHash]` to retrieve values or objects from that point in time.

Unlike git, Automerge does not track additional metadata about the changes over time, such as who contributed any change, or at what time the change was initially created. 

### Grouping edits into changes

Edits you make to a document accumulate in a pending change until something commits it.
``Document/commitWith(message:timestamp:)`` commits the pending edits with a message and timestamp, and ``Document/rollback()`` discards them instead.
Reading ``Document/heads()``, calling ``Document/save()``, forking, merging, and syncing also commit the pending edits, without a message.

To make sure a group of edits lands in the history as exactly one change, apply them with ``Document/transact(message:timestamp:_:)``.
It commits what its body did as one change — or rolls it back if the body throws — and holds the document's lock while the body runs, so a save or sync on another thread can't commit part of the group early.

### Forking and Merging

You can create a fork a document using ``Document/fork()``, or ``Document/forkAt(heads:)`` to get a fork of the document at a specific point in time.
Likewise, you can merge one Document into another using ``Document/merge(other:)``, which applies any changes from the other document.

When working with multiple documents, it is important that the documents source with the same shared history, or merges (or sync) may have unpredictable, although consistent, results.
To take full advantage of Automerge's capabilities, work from forks of a single document rather than creating separate Documents, even with the same schema.

### Getting notified of what changed

When you apply changes received from a remote document (or merged from a separate local document) you may want to know what changed within the `Document`, for example to update an app's user interface.
To get this detail, use ``Document/receiveSyncMessageWithPatches(state:message:)``, which operates like `Document/receiveSyncMessage(state:message:)`, and additionally returns an array of patches, represented by the type ``Patch``.

Inspect a patch to see what action Automerge applied by inspecting the ``Patch/action`` property (represented by the enumeration ``PatchAction``).
The property ``Patch/path`` represents the path through the document schema to the element that was updated, represented by an array of ``PathElement``.
`PathElement` has an object Id (``PathElement/obj``) property and a ``PathElement/prop`` property.
`Prop` is an enumeration that represents either a key to a dictionary and it's value, or the index location within an array.
