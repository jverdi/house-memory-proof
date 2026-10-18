# Semantic CSV, schema 1

Tools → Export semantic CSV produces a UTF-8 CSV with a header, quoted cells and CRLF records. It includes **all** project features, including hidden features, every ordered route point, both route endpoints, measurements and explicit service connections. The geometry scope controls do not filter metadata exports; the interface states this. Complete metadata JSON and the house archive remain the lossless formats.

`record_type` identifies `feature`, `route_point`, `endpoint`, `measurement` or `connection`. UUIDs retain their source identities. Child IDs append `:route:N` or `:endpoint:N`; `parent_id` is the source feature UUID. Route indices start at zero; endpoint indices are 0=start and 1=end. A connection links the explicit feature IDs and endpoint indices; proximity does not establish connectivity. `confirmed` and `reviewed` record user decisions, not surveyed accuracy.

Coordinates and lengths use metres, right-handed X-east/Y-north/Z-up axes, with locale-independent decimal points. **Read `coordinate_frame` before combining points.** `house` denotes stored house coordinates; `segment:UUID` denotes that capture's original local coordinates, even when registered. The exporter never applies a transform. A feature/measurement's `registration_json` contains its segment ID, optional local-to-house rigid `transform`, user approval and optional residual. Child points inherit their parent's registration. Missing transforms remain missing; they must not be treated as identity registration. No registration establishes physical precision by itself.

Dates are UTC ISO 8601. Features have `stage_date`, not an invented feature-capture date. Measurements and connections have their recorded `date`. `source_ids_json` retains observation/source identities. `provenance_json` retains the semantic source object and annotation dependencies; for features it excludes mesh, route arrays (exported as child rows), UV arrays and per-vertex photo tracks. Detailed geometry and those tracks remain in metadata JSON/archive. Provenance object dates use ISO 8601; standalone metadata JSON keeps the existing app encoding.

Text cells whose first non-whitespace character is `=`, `+`, `-`, `@` or an apostrophe, or which begin with tab/CR/LF, receive one leading apostrophe to prevent spreadsheet formula interpretation. Literal leading apostrophes are therefore escaped too. To recover original text, remove exactly one initial apostrophe from a non-numeric cell when present. Numeric columns remain numeric, including negative coordinates and levels. Standard CSV parsing recovers commas, quotes, Unicode and embedded newlines.

The writer streams records, admits at most 128 MB total and 2 MB per field, checks cancellation between records and removes incomplete output on failure. It does not load textures or original media. Empty projects produce the header. The native fixture and independent Python `csv` reader verify separate/registered/house frames, route order, connection indices, measurements, identity, dates, hidden records and text escaping. This format summarizes records; it is not a precision certificate or replacement for the complete archive.

IFC-derived features additionally carry `ifcSourceCoordinates` in
`provenance_json`: a Z-up metre origin, converter/schema/unit labels and retained
MapConversion/CRS fields. Add the origin to local source-frame coordinates to
recover project metres, before any separate segment-to-house registration. The
CRS records are documentary and are not applied. Unknown house alignment remains
unknown. Mesh positions themselves remain in the archive/GLB; this CSV remains a
semantic summary. The independent reader validates these optional records and
requires the original source/segment identities.
