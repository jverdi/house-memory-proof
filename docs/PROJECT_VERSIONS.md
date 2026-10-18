# Project reader versions

New projects and app commits use house schema **2**. New service fields, imported-coordinate declarations and photo annotations must not be silently discarded by an older schema-1 app. Earlier builds' explicit `schema == 1` admission guard makes them refuse schema-2 projects. Standard geometry/movie exports remain usable through their own formats; complete project archives require a compatible app or portable reader.

The current reader accepts schemas 1 and 2. Schema-1 metadata upgrades to schema 2 in memory, preserving identities, observations, originals and known optional fields. Reading an archive or database row does not rewrite its source bytes. A subsequent app commit writes version 2 through the existing atomic revision mechanism. The legacy database migration fixture deliberately retains schema-1 metadata to exercise the real upgrade path.

Unsupported schema numbers fail before project activation. The app must not change an unknown future version to 2 to make it load. Repository recovery keeps the original row and recovery copy; archive validation does not change the package. ZIP/archive manifest version and semantic CSV version remain 1 because those container contracts are unchanged.

Native checks cover version-1 identity/content preservation, version-2 serialization and unknown future refusal alongside the existing interrupted SQLite migration/snapshot checks. The independent portable reader checks both supported versions and rejects 0, 3 and 999 without writing to the input. This is a reader/version contract; a complete old/new signed-build and provider handoff matrix remains separate release acceptance work.
