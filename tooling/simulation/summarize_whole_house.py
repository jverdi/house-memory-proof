"""Allowlist aggregate metrics; never publish query/source/geometry records."""
import argparse
import json
import math
from pathlib import Path

COUNTS=['positiveQueries','positiveAccepted','negativeQueries','falseAccepts','expectedMapCount','mapCount','mapViews','optimizedCameraCount']
SCALARS=['p95Metres','worstAcceptedPositionErrorMetres','maximumOptimizedCameraPositionErrorMetres']


def number(value):
    return value if type(value) in [int,float] and math.isfinite(value) and value>=0 else None


def distribution(source):
    return {key:number(source.get(key)) for key in ['count','p50','p95','maximum']}


def summarize(folder):
    cases=[]
    for stage in ['rough','finished']:
        case=dict(stage=stage,complete=False,passed=False)
        try:
            report=json.loads((folder/(stage+'-replay.json')).read_text())
            generated=json.loads((folder/(stage+'-generator.json')).read_text())
            checked=json.loads((folder/(stage+'-bundle-check.json')).read_text())
            case.update(complete=True,passed=report.get('passed') is True and checked.get('passed') is True,
                rooms=number(generated.get('rooms')),levels=number(generated.get('levels')),width=number(generated.get('width')),
                inputArchiveCheckPassed=checked.get('passed') is True,oracleReadDenied=report.get('oracleReadDenied') is True,queryLabelsExcluded=report.get('queryLabelsExcluded') is True)
            for key in COUNTS+SCALARS:case[key]=number(report.get(key))
            case['rotationErrorDegrees']=distribution(report.get('rotationErrorDegrees',{}))
            overlay=report.get('visibleSurfaceOverlay',{})
            case['visibleSurfaceOverlay']=dict(scoredAcceptedQueries=number(overlay.get('scoredAcceptedQueries')),samples=number(overlay.get('samples')),behindCamera=number(overlay.get('behindCamera')),
                worldMetres=distribution(overlay.get('worldMetres',{})),reprojectionPixels=distribution(overlay.get('reprojectionPixels',{})),diagnosticOnly=True,alignmentToTruth=False)
            if any(case[k] is None for k in COUNTS+SCALARS):case.update(passed=False,complete=False)
        except Exception as error:case.update(complete=False,passed=False,errorClass=type(error).__name__)
        cases.append(case)
    return dict(cases=cases,complete=all(c['complete'] for c in cases),passed=all(c['passed'] for c in cases),rawEvidencePublished=False,physicalQualification=False)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('private',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(summarize(a.private),indent=2,allow_nan=False)+'\n')
