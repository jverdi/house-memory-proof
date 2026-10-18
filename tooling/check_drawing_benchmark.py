#!/usr/bin/env python3
"""Independently score analytic shipping-Vision proposals, by method and size."""
import argparse
from collections import defaultdict
import json
import math
from pathlib import Path


def require(ok,message):
    if not ok:raise ValueError(message)


def box(row):
    values=row.get('box')
    require(isinstance(values,list) and len(values)==4 and all(type(v) in (int,float) and math.isfinite(v) for v in values),'Invalid box')
    x0,y0,x1,y1=values
    require(x1>x0 and y1>y0,'Empty box')
    return values


def score(report):
    require(report.get('schema')==1 and report.get('executionPassed') is True,'Incomplete benchmark')
    for name in ['accuracyQualified','protectedBenchmark','physicalQualification','semanticClassifierAvailable']:
        require(report.get(name) is False,'Unsupported qualification claim')
    cases=report.get('cases');require(isinstance(cases,list) and len(cases)==11,'Expected eleven frozen development cases')
    aggregate=defaultdict(lambda:dict(truth=0,matched=0,falsePositive=0))
    negative_predictions=0
    for index,case in enumerate(cases):
        require(case['case']==index and case['allUnreviewed'] is True,'Case identity/review mismatch')
        truth=case['truth'];predictions=case['predictions']
        require(case['proposals']==len(predictions)<=216,'Unbounded/missing predictions')
        require(len(truth)==(5 if index<8 else 0),'Unexpected analytic target inventory')
        expected=defaultdict(lambda:dict(truth=0,matched=0,falsePositive=0));used=set()
        for target in truth:
            key=target['category']+'/'+target['size'];expected[key]['truth']+=1
            x0,y0,x1,y1=box(target)
            for i,prediction in enumerate(predictions):
                px0,py0,px1,py1=box(prediction)
                require(prediction.get('reviewed') is False,'Proposal already reviewed')
                if i in used:continue
                if target.get('text') is not None:
                    hit=prediction['kind']=='Room name' and ' '.join(prediction['label'].upper().split())==target['text'] and x0<=(px0+px1)/2<=x1 and y0<=(py0+py1)/2<=y1
                else:
                    overlap=max(0,min(x1,px1)-max(x0,px0))*max(0,min(y1,py1)-max(y0,py0))
                    union=(x1-x0)*(y1-y0)+(px1-px0)*(py1-py0)-overlap
                    hit=prediction['kind']=='Possible boundary' and union>0 and overlap/union>=.75
                if hit:
                    used.add(i);expected[key]['matched']+=1;break
        for i,prediction in enumerate(predictions):
            require(prediction.get('reviewed') is False,'Proposal already reviewed')
            x0,y0,x1,y1=box(prediction)
            if i in used:continue
            if prediction['kind']=='Possible boundary':category='rectangular-outline';size='small' if x1-x0<260 else 'large'
            else:
                require(prediction['kind']=='Room name','Unknown proposal method')
                category='unmatched-text';size='18px' if y1-y0<24 else '36px'
            expected[category+'/'+size]['falsePositive']+=1
        require(dict(expected)==case['counts'],'Native and independent matching disagree')
        require(sum(c['matched']+c['falsePositive'] for c in expected.values())==len(predictions),'Prediction census mismatch')
        if index>=8:negative_predictions+=len(predictions)
        for key,counts in expected.items():
            for name,value in counts.items():aggregate[key][name]+=value
    rows=[];methods=defaultdict(lambda:dict(truth=0,matched=0,falsePositive=0))
    for key,counts in sorted(aggregate.items()):
        category,size=key.split('/')
        # OCR proposes text; it does not independently predict semantic type.
        rows.append(dict(category=category,size=size,**counts,recall=counts['matched']/counts['truth'] if counts['truth'] else None,
            precision=counts['matched']/(counts['matched']+counts['falsePositive']) if category=='rectangular-outline' and counts['matched']+counts['falsePositive'] else None))
        method=('rectangle' if category=='rectangular-outline' else 'OCR')+'/'+size
        for name,value in counts.items():methods[method][name]+=value
    method_rows=[]
    for key,c in sorted(methods.items()):
        method,size=key.split('/');denominator=c['matched']+c['falsePositive']
        method_rows.append(dict(method=method,size=size,**c,precision=c['matched']/denominator if denominator else None,recall=c['matched']/c['truth'] if c['truth'] else None))
    return dict(passed=True,reader='Independent analytic drawing suggestion scorer',profileHash=report['profileHash'],cases=len(cases),classSizeCounts=rows,methodSizeMetrics=method_rows,negativeCaseProposals=negative_predictions,
        accuracyQualified=False,physicalQualification=False,protectedBenchmark=False,
        limitations='Counts scored on eleven analytic development rasters only. OCR semantic subtype precision is unavailable; text/rectangle precision and recall are reported separately by size. No thresholds, model or operating envelope changed.')


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('input',type=Path);parser.add_argument('--output',type=Path);args=parser.parse_args()
    require(args.input.stat().st_size<2_000_000,'Benchmark too large')
    report=score(json.loads(args.input.read_text()));data=json.dumps(report,indent=2,allow_nan=False)+'\n'
    if args.output:
        require(args.output.resolve()!=args.input.resolve(),'Do not overwrite source evidence')
        args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(data)
    print(data,end='')


if __name__=='__main__':main()
