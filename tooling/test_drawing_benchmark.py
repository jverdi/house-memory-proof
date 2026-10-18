import copy
import unittest
from check_drawing_benchmark import score


def fixture():
    cases=[]
    for index in range(11):
        truth=[];predictions=[];counts={}
        if index<8:
            for i in range(2):
                truth.append(dict(category='rectangular-outline',size='small',box=[i*300,0,i*300+200,200],text=None))
                predictions.append(dict(kind='Possible boundary',box=[i*300,0,i*300+200,200],label='Possible boundary',reviewed=False))
                truth.append(dict(category='room-name-text',size='18px',box=[i*300+40,80,i*300+160,100],text='ROOM '+str(i)))
                predictions.append(dict(kind='Room name',box=[i*300+50,82,i*300+150,98],label='ROOM '+str(i),reviewed=False))
            truth.append(dict(category='service-label-text',size='18px',box=[40,300,160,320],text='CAT6'))
            predictions.append(dict(kind='Room name',box=[50,302,150,318],label='CAT6',reviewed=False))
            counts={'rectangular-outline/small':dict(truth=2,matched=2,falsePositive=0),'room-name-text/18px':dict(truth=2,matched=2,falsePositive=0),'service-label-text/18px':dict(truth=1,matched=1,falsePositive=0)}
        cases.append(dict(case=index,allUnreviewed=True,proposals=len(predictions),truth=truth,predictions=predictions,counts=counts))
    return dict(schema=1,executionPassed=True,accuracyQualified=False,protectedBenchmark=False,physicalQualification=False,semanticClassifierAvailable=False,profileHash='profile',cases=cases)


class DrawingBenchmarkReader(unittest.TestCase):
    def test_class_size_metrics_and_no_semantic_precision_claim(self):
        result=score(fixture());self.assertFalse(result['accuracyQualified'])
        self.assertEqual(result['negativeCaseProposals'],0)
        for row in result['methodSizeMetrics']:
            self.assertEqual(row['precision'],1);self.assertEqual(row['recall'],1)
        for row in result['classSizeCounts']:
            if row['category']!='rectangular-outline':self.assertIsNone(row['precision'])
        data=fixture();row=data['cases'][8]
        row['predictions']=[dict(kind='Room name',box=[0,0,20,10],label='FALSE',reviewed=False)]
        row['proposals']=1;row['counts']={'unmatched-text/18px':dict(truth=0,matched=0,falsePositive=1)}
        result=score(data);self.assertEqual(result['negativeCaseProposals'],1)
        ocr=next(r for r in result['methodSizeMetrics'] if r['method']=='OCR')
        self.assertEqual(ocr['precision'],24/25)

    def test_false_counts_review_and_geometry_refused(self):
        for mutation in range(4):
            data=fixture()
            if mutation==0:data['cases'][0]['counts']['rectangular-outline/small']['matched']=1
            elif mutation==1:data['cases'][0]['predictions'][0]['reviewed']=True
            elif mutation==2:data['cases'][0]['predictions'][0]['box']=[0,0,float('nan'),20]
            else:data['cases'][0]['predictions'][1]['label']='OTHER'
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):score(data)


if __name__=='__main__':unittest.main()
