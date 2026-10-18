"""Independent reader for raw IFC properties; no IFC geometry reconstruction."""
import json
import math
import re

GUID=re.compile(r'[0-3][0-9A-Za-z_$]{21}')
HASH=re.compile(r'[0-9a-f]{64}')
EXCLUDED=['OwnerHistory','Representation','RepresentationMaps']

def need(ok,message):
    if not ok:raise ValueError('IFC properties: '+message)

def identifier(value):
    need(type(value) is int and 0<value<=2147483647,'invalid EXPRESS identity')
    return value

def scalar(value):
    return value.get('value') if isinstance(value,dict) and 'value' in value else value

def object_check(value):
    need(isinstance(value,dict),'missing object identity')
    identifier(value.get('expressID'))
    for key in ['guid','typeName']:
        text=value.get(key);need(isinstance(text,str) and len(text.encode())<=4096 and '\0' not in text,'invalid object text')
    need(bool(value['typeName']),'missing object type')
    status=value.get('guidStatus');need(status in ['valid','duplicate','missing','malformed'],'invalid GUID status')
    need(status not in ['valid','duplicate'] or GUID.fullmatch(value['guid']) is not None,'invalid compressed GUID')
    need(status!='missing' or value['guid']=='','missing GUID has a value')

def reference_check(value,source_asset):
    need(isinstance(value,dict),'missing property reference')
    sha=value.get('sourceSHA256');need(isinstance(sha,str) and HASH.fullmatch(sha) and source_asset==sha+'.ifc','original checksum differs')
    asset=value.get('asset');need(isinstance(asset,str) and re.fullmatch(r'[0-9a-f]{64}\.json',asset),'invalid sidecar identity')
    need(isinstance(value.get('summary'),dict),'missing summary')
    summary=value['summary'];keys=['products','representedProducts','convertedProducts','unconvertedRepresentedProducts','storeys','records','malformedGUIDs','missingGUIDs','duplicateGUIDs']
    need(set(summary)==set(keys) and all(type(summary[k]) is int and summary[k]>=0 for k in keys),'invalid summary counts')
    n=summary['products'];need(n<=10000 and n<=summary['records']<=20000 and summary['storeys']<=100,'summary inventory limit')
    need(summary['representedProducts']<=n and summary['convertedProducts']<=n and summary['unconvertedRepresentedProducts']<=summary['representedProducts'] and sum(summary[k] for k in ['malformedGUIDs','missingGUIDs','duplicateGUIDs'])<=n,'inconsistent summary')

def validate(data,reference,source_asset,features):
    reference_check(reference,source_asset);need(len(data)<=4_000_000,'sidecar byte limit')
    def pairs(items):
        result={}
        for key,value in items:need(key not in result,'duplicate JSON key');result[key]=value
        return result
    root=json.loads(data,object_pairs_hook=pairs)
    stack=[(root,0)];count=0
    while stack:
        value,depth=stack.pop();count+=1;need(count<=250000 and depth<=22,'value/nesting limit')
        if isinstance(value,str):need(len(value.encode())<=4096 and '\0' not in value,'text limit')
        elif isinstance(value,dict):
            need(len(value)<=2000,'field limit');stack.extend((v,depth+1) for pair in value.items() for v in pair)
        elif isinstance(value,list):need(len(value)<=20000,'list limit');stack.extend((v,depth+1) for v in value)
        elif type(value) in (float,int):need(math.isfinite(value),'nonfinite number')
        else:need(value is None or type(value) is bool,'unknown JSON value')
    need(type(root.get('version')) is int and root['version']==1 and root.get('converter')=='web-ifc-0.0.72','format mismatch')
    need(root.get('rawSourceValues') is True and root.get('excludedForwardFields')==EXCLUDED and isinstance(root.get('sourceSchema'),str) and root['sourceSchema'],'source semantics missing')
    need(root.get('sourceSHA256')==reference['sourceSHA256'],'source hash mismatch')
    for name,limit in [('records',20000),('products',10000),('storeys',100)]:need(isinstance(root.get(name),list) and len(root[name])<=limit,'inventory limit')
    rows={}
    for row in root['records']:
        key=identifier(row.get('expressID'));need(key not in rows and isinstance(row.get('fields'),dict) and isinstance(row.get('typeName'),str) and row['typeName'],'invalid record');rows[key]=row
    for row in rows.values():
        pending=[v for k,v in row['fields'].items() if k not in EXCLUDED]
        while pending:
            value=pending.pop()
            if isinstance(value,dict):
                if type(value.get('type')) is int and value['type']==5:need(identifier(value.get('value')) in rows,'missing forward reference')
                else:pending.extend(value.values())
            elif isinstance(value,list):pending.extend(value)
    products={};guids={};represented=set();converted=set()
    for product in root['products']:
        object_check(product);key=product['expressID'];need(key not in products and key in rows,'invalid product inventory')
        fields=rows[key]['fields'];raw_guid=scalar(fields.get('GlobalId'));guid=raw_guid if isinstance(raw_guid,str) else ''
        need(product['guid']==guid and product['typeName']==rows[key]['typeName'],'identity differs from source')
        need(type(product.get('converted')) is bool and type(product.get('represented')) is bool,'missing coverage')
        need(product['represented']==(fields.get('Representation') is not None),'representation differs')
        if product['represented']:represented.add(key)
        if product['converted']:converted.add(key)
        if GUID.fullmatch(guid):guids[guid]=guids.get(guid,0)+1
        products[key]=product
    for key,product in products.items():
        raw_guid=scalar(rows[key]['fields'].get('GlobalId'));guid=product['guid']
        status='missing' if raw_guid is None or raw_guid=='' else 'malformed' if not GUID.fullmatch(guid) else 'duplicate' if guids[guid]>1 else 'valid'
        need(status==product['guidStatus'],'GUID warning mismatch')
    seen=set()
    for storey in root['storeys']:
        key=identifier(storey.get('expressID'));need(key in products and key not in seen,'invalid storey identity');seen.add(key)
        fields=rows[key]['fields'];elevation=scalar(fields.get('Elevation'));saved=storey.get('elevation')
        need((elevation is None and saved is None) or (type(elevation) in (int,float) and type(saved) in (int,float) and saved==elevation),'storey elevation differs')
        need(storey.get('name')==(scalar(fields.get('Name')) or ''),'storey name differs')
    summary=dict(products=len(products),representedProducts=len(represented),convertedProducts=len(converted),unconvertedRepresentedProducts=len(represented-converted),storeys=len(seen),records=len(rows),**{label:sum(p['guidStatus']==status for p in products.values()) for label,status in [('malformedGUIDs','malformed'),('missingGUIDs','missing'),('duplicateGUIDs','duplicate')]})
    need(root.get('summary')==summary and reference['summary']==summary and all(type(v) is int for item in [root['summary'],reference['summary']] for v in item.values()),'summary differs')
    for feature in features:
        value=feature.get('ifcObject');object_check(value);key=value['expressID']
        need(key in converted and all(value[k]==products[key][k] for k in ['expressID','typeName','guid','guidStatus']),'feature identity differs')
    return summary
