"""Explicit delivery gate; upload success alone does not establish readiness."""
def ready_for_owner(report):
    if report.get('personal_account_holder_verified') is not True or report.get('owner_has_testflight_access') is not True:return False
    target=report.get('target_build')
    builds=[b for b in report.get('builds',[]) if not target or b.get('version')==target]
    if target and len(builds)!=1:return False
    return any(b.get('processing_state')=='VALID' and b.get('expired') is False
        and b.get('beta_state',{}).get('internalBuildState')=='IN_BETA_TESTING'
        and any(g.get('name')=='Personal iPhone' and g.get('internal') is True for g in b.get('groups',[]))
        for b in builds)
