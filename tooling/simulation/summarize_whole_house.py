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


def failure_categories(source):
    # Fixed labels only: never emit exception text, paths, UUIDs or source poses.
    categories={}
    prefixes=[('Capture at least two overlapping','input-admission'),
        ('Not enough stable, textured depth features','depth-texture-support'),
        ('Pose refinement needs at least three','pose-view-count'),
        ('Fewer than three photographs share reliable overlap','pose-overlap'),
        ('Insufficient independently matched overlap','pose-loop-support'),
        ('Pose graph rejected','pose-consistency'),
        ('Too few independently checked photograph details','photo-track-support'),
        ('Joint refinement needs twenty','bundle-anchor-support'),
        ('Joint refinement did not pass','bundle-held-out-check'),
        ('Camera matching reached','pose-time-budget'),
        ('Photograph matching reached','photo-time-budget')]
    for message in source.values():
        category=next((label for prefix,label in prefixes if isinstance(message,str) and message.startswith(prefix)),'unclassified')
        categories[category]=categories.get(category,0)+1
    return categories


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
            case['sceneVariant']=generated.get('sceneVariant') if generated.get('sceneVariant') in ['baseline','windows-clutter'] else 'unspecified'
            case['sceneInventory']={key:number(generated.get(key)) for key in ['windows','clutterObjects','materialFamily']}
            case['mappingFailureCategories']=failure_categories(report.get('mappingFailures',{}))
            case['rotationErrorDegrees']=distribution(report.get('rotationErrorDegrees',{}))
            overlay=report.get('visibleSurfaceOverlay',{})
            case['visibleSurfaceOverlay']=dict(scoredAcceptedQueries=number(overlay.get('scoredAcceptedQueries')),samples=number(overlay.get('samples')),behindCamera=number(overlay.get('behindCamera')),
                worldMetres=distribution(overlay.get('worldMetres',{})),reprojectionPixels=distribution(overlay.get('reprojectionPixels',{})),diagnosticOnly=True,alignmentToTruth=False)
            expected=case.get('positiveQueries'),case.get('negativeQueries')
            if any(case[k] is None for k in COUNTS) or any(type(n) is not int for n in expected) or len(report.get('queries',[]))!=sum(expected):
                case.update(passed=False,complete=False)
            # A complete refusal legitimately has no accepted-pose percentile
            # or optimized source pose. That absence is not a missing query.
            # It can never manufacture a passing nominal spatial result.
            if any(case[k] is None for k in SCALARS):case['passed']=False
            if case.get('positiveAccepted',0)>0 and case['p95Metres'] is None:case['complete']=False
            if case.get('optimizedCameraCount',0)>0 and case['maximumOptimizedCameraPositionErrorMetres'] is None:case['complete']=False
        except Exception as error:case.update(complete=False,passed=False,errorClass=type(error).__name__)
        cases.append(case)
    return dict(cases=cases,complete=all(c['complete'] for c in cases),passed=all(c['passed'] for c in cases),rawEvidencePublished=False,physicalQualification=False)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('private',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(summarize(a.private),indent=2,allow_nan=False)+'\n')
