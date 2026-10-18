# Project reader versions

The next candidate writes house schema **3**. Reversible IFC origins and source
CRS records must not disappear through an older writer: losing an origin could
move a design by kilometres. Schema-1 and schema-2 builds refuse version 3
through their existing explicit admission guard. Standard model/movie exports
retain their own formats; full project archives require a compatible reader.

The candidate accepts schemas 1, 2 and 3. Earlier metadata upgrades to version 3
in memory, preserving identities, observations, originals and known optional
fields. Opening an archive or database row does not rewrite its source bytes.
A subsequent app commit writes version 3 through the atomic revision mechanism.
The interrupted database migration fixture deliberately retains schema 1.

Unsupported schema numbers fail before project activation. An unknown future
version is never relabeled to force it to load. Recovery keeps the original row
and recovery copy; archive validation does not change the package. ZIP/archive
manifest and semantic CSV versions remain 1; their container contracts are
unchanged. CSV's extensible provenance JSON now also carries IFC coordinates.

Native checks cover both predecessors, current serialization and future refusal.
The independent portable reader checks versions 1/2/3 and rejects 0/4/999 without
writing to its input. Exact native validation of schema 3 is pending. The earlier
schema-2 path passed at fb2f9201d6 (build 199.1). A complete signed old/new-app and
provider handoff matrix remains separate release acceptance work.
