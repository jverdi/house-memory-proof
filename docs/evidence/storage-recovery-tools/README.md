# Before/after recovery comparison

This helper validates both complete `.hxray` archives using the existing independent reader, then compares all project metadata and every original's manifest hash. It never extracts the archives or modifies them. ZIP encoding, archive filenames and the generated index/viewer bytes may differ; the evidence metadata and original asset inventory must not.

For an update, no project metadata differences are silently accepted. For a restore into a new project, only a new project ID, the exact ` · restored` name suffix, and revision zero are allowed. Unexpected schema additions, default-value migrations or reordered records require review instead of an automatic pass. This strict comparison is intentionally conservative.

Run from the repository:

```sh
python3 docs/evidence/storage-recovery-tools/compare_archives.py BEFORE.hxray AFTER.hxray --mode update --output update-comparison.json
python3 docs/evidence/storage-recovery-tools/compare_archives.py AFTER.hxray RESTORED.hxray --mode restore --output restore-comparison.json
python3 -m unittest discover -s docs/evidence/storage-recovery-tools -p 'test_*.py'
```

Five local contract tests pass using the retained real earlier-writer **synthetic** archive. They check same content/different ZIP encoding, changed notes/identity/revision, exact restore identity rules, corruption, read-only inputs and aggregate-only reports. This is not an actual installed-version migration test.

## Device evidence needed to close the real update gate

1. Keep the current installation. In a disposable project, export a complete archive **before** updating, plus a screenshot of the installed build/source and exported diagnostics. Retain a second independent copy. Do not uninstall.
2. After the replacement build has passed CI and is actually available in TestFlight, install it as an update. Record its build/source. Reopen the same project without edits and export the **after** archive and diagnostics.
3. Restore the retained archive as a separate project and export that restored project. Confirm the original project remains present and usable.
4. Return the three archives and build/diagnostic evidence privately. Run both comparisons and inspect every difference. A pass compares saved contents; it does not prove the signed installation or provider retrieval occurred. Keep the physical execution record separate.

## Provider evidence needed separately

Use a dedicated folder and synthetic project only. Retain independent source/archive copies. Record actual upload state, restore from a clean destination, offline local use, delayed/partial arrival, missing destination, conflicts and permission loss. Quota refusal and account transitions stay **not exercised** unless they can be performed safely and intentionally; do not fill the main phone's storage, change a paid plan, or sign out of its primary Apple account just to manufacture a test condition.

The aggregate report excludes project names, project IDs, original filenames and captured content. Do not publish the actual input archives, screenshots or account/provider metadata. `actualSignedUpdateVerified` and `actualProviderRecoveryVerified` remain false in this tool: separate physical execution evidence is required to change the overall acceptance record.
