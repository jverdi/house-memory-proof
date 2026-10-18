# Incremental snapshot format

Version 2 stores immutable objects under `HouseXraySnapshots`. It remains separate from the live SQLite store and from full `.hxray` archives. The reader continues to accept version 1 snapshots.

| Directory | Contents |
|---|---|
| `chunks` | SHA-256-named objects of at most 16 MiB |
| `metadata` | Canonically encoded project JSON, at most 100 MB |
| `manifests` | SHA-256-named version 2 chunk indexes, at most 32 MB |
| `revisions` | Discoverable commit records, published after all required objects verify |

Each manifest records the project, metadata hash, installation-specific random device ID, parent metadata identity, and original asset identities. Each original has a byte length and an ordered list of chunk ranges. The writer packs small originals together and splits large originals. An unchanged original reuses its parent's complete range list, so adding a file does not repack previous content. No chunk or original is automatically deleted.

The revision identity is derived from the metadata content with a version-specific namespace. Retrying after the commit point returns the same verified revision. Different content remains separate even when two copies reuse a revision number. Concurrent writers can retain separate parent branches; choosing a revision to restore never merges their geometry. The catalog is the discovery mechanism; there is no shared mutable pointer whose arrival could hide a branch.

Publication uses coordinated file access, temporary files, hash readback, and a small final revision record. Cross-file provider arrival is not atomic. A reader verifies metadata, manifest, every chunk range, and each reconstructed original before returning a separate restored project. Missing, truncated, corrupt, future-version, and contradictory records cannot replace a healthy project. Valid content-addressed originals copied before a later failure may remain locally, but no restored project is activated.

Transfer inspection checks every required file and distinguishes reported uploaded, uploading, waiting, unavailable, conflicting, failed, and unknown-provider states. A local hash check does not imply cloud upload. Even an all-uploaded report does not prove recovery on another destination or device. No missing file, conflict, or error is counted as uploaded.

For a selected iCloud folder, an account identity change stops access at operation checkpoints and requires selecting the folder again. The identity token stays in local preferences and is not included in snapshots or diagnostics. Other Files providers expose only the capabilities and state reported by iOS; changed or stale folder permission is refused.

Native qualification includes packing and boundary splitting, incremental reuse, legacy reading, interruption before and after publication, retry identity, missing/corrupt arrivals, invalid ranges and contradictory indexes. A separate Python reader reconstructs known originals from actual Swift output. These checks do not qualify real iCloud quota/account transitions, background transfer, sudden power loss, or owner-device capacity.
