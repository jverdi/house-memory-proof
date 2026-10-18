# Project reader versions

The next candidate writes house schema **4** to retain checksummed IFC property
sidecars and source-object references. Schema 3 introduced reversible IFC
origins/CRS; losing an origin could move design geometry by kilometres. Older
readers reject unsupported versions before writing, preventing silent field loss.
Standard model/movie exports retain their own formats; full project archives
require a compatible reader.

The candidate accepts schemas 1, 2, 3 and 4. Earlier metadata upgrades in memory,
preserving identities, observations, originals and known optional fields.
Opening an archive or database row never rewrites its source bytes. A subsequent
app commit writes schema 4 through the atomic revision mechanism. The interrupted
database migration fixture deliberately retains schema 1.

Unsupported versions fail before activation; an unknown version is never relabeled.
Recovery keeps the original database row and recovery copy. ZIP/archive manifest
and semantic CSV versions remain 1; CSV provenance adds optional IFC coordinates,
source-object identity and the documentary property sidecar reference.

Native checks cover all predecessors, current serialization and future refusal.
The independent reader checks versions 1/2/3/4 and rejects 0/5/999 without changing
the input. Schema 3 passed native checks at fa9785efe79 (140 total); schema 4 and
property asset handoff are prepared for the next native run. Complete signed
old/new-app and provider handoff remain separate acceptance work.
