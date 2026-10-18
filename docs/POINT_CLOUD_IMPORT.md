# Point-cloud source declarations

Importing PLY first saves the original as an immutable drawing/source asset. The bounded ASCII parser runs on the local worker. Unsupported records or parsing cancellation leave that source available in Drawings & design references. The original file is never rewritten.

Geometry requires explicit units (metres, millimetres, centimetres, feet or inches), upright axis (Z up or Y up) and room association. Both coordinate choices start at Unknown. Saved sources can reopen the same importer from their source page. Keep source only closes the importer without generating geometry. Units scale coordinates to metres; the right-handed Y-up conversion is `(x, -z, y)`. No translation, orientation relative to the house, registration, precision or measurement calibration is inferred.

Each accepted import gets a documentary stage and a separate unregistered source frame. Geometry remains separate until explicitly aligned. The feature retains the original source ID, declared units/axis and a fingerprint of source content plus those declarations. Changing the source/declaration invalidates dependent geometry. Archive JSON, CSV provenance and GLB extras preserve this record. Independent archive admission requires known declarations, the PLY original and a source frame.

The input remains capped at 50 MB, 200,000 vertices and 400,000 triangles. The parser still rejects binary/unsupported records, malformed fields, nonfinite/out-of-bounds coordinates and invalid topology. Unsupported formats remain source-only. Earlier PLY imports are left unchanged; Object details identifies their old metre assumption rather than retroactively claiming a declaration.

The native contract exercises all ten unit/axis combinations, unknown declarations, stale source refusal, dependent-geometry invalidation, source byte preservation and archive restore. Native and interface evidence remains required; no physical importer accuracy is certified.
