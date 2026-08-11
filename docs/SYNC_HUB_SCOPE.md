# Novel Grabber as the sync hub

Scoping note. Not a commitment — the point is to size the work and name
the decisions before any of it starts.

## Why consider it

Sync today runs through iCloud Documents via two Swift bridges. That works
well and costs nothing to run, but it ties every synced feature to Apple.
Any non-Apple device — an Android phone, a Boox, a desktop reader — gets
no reading progress, no bookmarks, no streaks, no saved views.

Meanwhile there is already an always-on server that both devices
authenticate against and that owns the library itself. It is the obvious
hub, and arguably the one you would have picked had it existed first.

## What has to move

Eleven blobs, each with its own merge rule that already exists and is
tested:

| store | merge rule |
| --- | --- |
| reading progress | per-volume LWW on `updatedAt` |
| reading activity | per-device ledgers, per-day max (monotonic) |
| bookmarks | union by id |
| collections | whole-set LWW on modified time |
| saved views | whole-set LWW |
| library view | whole-value LWW |
| reader settings | LWW |
| series status | per-series LWW with tombstones |
| glossary | union by id, furthest sighting wins |
| custom themes | union by id |
| recommendation feedback | LWW |

**The merge semantics do not change.** That is the single most important
fact in this document: every store already exposes
`exportSyncBlob`/`mergeSyncBlob`, and the rules inside them are
transport-agnostic. What changes is only where the blob is put and
fetched.

## Server side

Three endpoints and one table:

```
GET  /api/sync/<key>          -> {blob, revision, modifiedAt}
PUT  /api/sync/<key>          {blob, baseRevision} -> {revision} | 409
GET  /api/sync                -> {key: revision} for all keys
```

```sql
CREATE TABLE sync_blobs (
    key         TEXT PRIMARY KEY,
    blob        TEXT NOT NULL,
    revision    INTEGER NOT NULL DEFAULT 1,
    modified_at TEXT NOT NULL
);
```

The manifest endpoint is what makes this cheaper than iCloud: one small
request says which of the eleven changed, so a client fetches only those
instead of reading all of them on every pull.

`baseRevision` gives an optimistic-concurrency check. A client that
fetched revision 4, merged, and tries to write against 4 succeeds; if the
other device wrote first the server answers 409 and the client re-fetches
and re-merges. That is exactly the loop the stores already implement —
they were built to merge, not to overwrite — so a 409 is cheap rather than
a failure.

**Blob sizes matter.** The activity ledger and reading progress grow with
the library; a rough measure before building would decide whether these
stay TEXT in SQLite or become files on disk. Everything else is small.

## App side

`CloudSyncService` gains a transport seam. Its public surface —
`pushX()`, `pullAndMerge()`, `flushX()` — stays as it is; only `_get` and
`_set` change, and they are already the only two places that touch a
platform channel.

```dart
abstract class SyncTransport {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}
```

With `ICloudTransport` (today's bridges) and `ServerTransport` (the new
endpoints) behind it. That is a genuinely small change to a file whose
risky parts — the merges — are untouched.

## The decisions this forces

**1. One transport or both?** Running server-and-iCloud together means two
sources of truth and a merge between the mergers. Recommend picking one.

**2. What happens when the server is unreachable?** iCloud syncs whenever
Apple manages it, including on cellular away from home. The server syncs
only when you can reach it. With Tailscale that is most of the time, but
"most" is not "always", and reading on a train would queue rather than
sync. The pending-adds queue is the pattern to copy.

**3. Migration.** First run against the server has an empty hub and a full
local store, and must push rather than pull — otherwise a device syncs
itself empty. Same shape as the guard already in `SavedViewStore`: an
untouched install exports nothing rather than an empty set.

**4. Backups.** Sync becomes a server responsibility. The library database
already holds far more valuable data, so this mostly means "the existing
backup story now also covers reading state" — worth stating rather than
assuming.

## Size

Roughly, in the units this project has been using:

* **Server**: one table, three endpoints, tests — comparable to the
  duplicate-prevention work. Small.
* **App transport seam**: small, and low-risk because the merges are
  untouched.
* **Migration and offline queueing**: the real work, and where the bugs
  would be.
* **Verification**: needs two devices and deliberate conflict-making —
  edit the same book on both while one is offline, then reconnect.

The honest summary: **the mechanism is a couple of days; the confidence is
the expensive part.** Sync bugs are quiet and destructive — the activity
ledger erasure earlier this project is exactly the shape of thing that
would recur — so the tests matter more than the code.

## Recommendation

Not worth doing for its own sake while everything is Apple. It becomes
worth doing the moment a non-Apple device is real, and at that point it is
better than adding a second cloud backend, because it puts sync where the
data already lives.

If it happens: do it as a **transport swap, not a rewrite**. The merge
rules have been debugged the hard way, and they should not be touched
while the transport changes underneath them.
