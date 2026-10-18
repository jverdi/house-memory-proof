/* Bounded documentary property graph. Source strings are data, never code. */
(function(root){
  'use strict';
  const LIMIT={products:10000,storeys:100,records:20000,values:150000,bytes:4000000};
  const guidOK=s=>typeof s==='string'&&/^[0-3][0-9A-Za-z_$]{21}$/.test(s);
  const raw=v=>v&&typeof v==='object'&&Object.hasOwn(v,'value')?v.value:v;
  function prepare(api,model,types){
    let bytes=0,values=0;
    const encoder=new TextEncoder(),records=new Map();
    const omitted=new Set(['OwnerHistory','Representation','RepresentationMaps']);
    function numberID(value){if(!Number.isInteger(value)||value<=0||value>2147483647)throw Error('Invalid IFC metadata identity');return value}
    function text(value){if(typeof value!=='string'||value.length>4096||value.includes('\0'))throw Error('IFC property text exceeds its limit');const size=encoder.encode(value).length;if(size>4096)throw Error('IFC property text exceeds its limit');bytes+=size;if(bytes>LIMIT.bytes)throw Error('IFC properties exceed their byte budget');return value}
    function copy(value,depth=0){
      if(++values>LIMIT.values||depth>16)throw Error('IFC properties exceed their nesting/value budget');bytes+=16;if(bytes>LIMIT.bytes)throw Error('IFC properties exceed their byte budget');
      if(value==null)return null;
      if(typeof value==='string')return text(value);
      if(typeof value==='boolean')return value;
      if(typeof value==='number'){if(!Number.isFinite(value))throw Error('Nonfinite IFC property');return value}
      if(Array.isArray(value))return value.map(v=>copy(v,depth+1));
      if(typeof value!=='object')throw Error('Unsupported IFC property value');
      const result=Object.create(null);
      for(const key of Object.keys(value).sort()){if(value[key]!==undefined)result[text(key)]=copy(value[key],depth+1)}
      return result;
    }
    function ids(type,limit){if(typeof type!=='number')return [];const rows=api.GetLineIDsWithType(model,type,true);if(rows.size()>limit)throw Error('IFC property inventory exceeds its limit');const result=Array.from({length:rows.size()},(_,i)=>numberID(rows.get(i)));if(new Set(result).size!==result.length)throw Error('Repeated IFC metadata identity');return result.sort((a,b)=>a-b)}
    function references(value){
      if(!value||typeof value!=='object')return [];
      if(value.type===types.REF)return [numberID(value.value)];
      return (Array.isArray(value)?value:Object.values(value)).flatMap(references);
    }
    function read(seed){
      const pending=[seed];
      while(pending.length){
        const id=numberID(pending.pop());if(records.has(id))continue;
        if(records.size>=LIMIT.records)throw Error('IFC property graph exceeds its record limit');
        const line=api.GetLine(model,id,false);if(!line||line.expressID!==id)throw Error('IFC property reference is missing');
        const fields=Object.create(null);for(const key of Object.keys(line).sort()){if(!['expressID','type'].includes(key)&&line[key]!==undefined)fields[key]=copy(line[key])}
        const typeName=text(api.GetNameFromTypeCode(line.type));
        records.set(id,{expressID:id,typeName,fields});
        // Geometry and ownership graphs stay in the immutable original IFC.
        // Iterate rather than recursively following arbitrary imported chains.
        for(const [key,value] of Object.entries(fields))if(!omitted.has(key))for(const ref of references(value))if(!records.has(ref))pending.push(ref);
      }
    }
    const productIDs=ids(types.IFCPRODUCT,LIMIT.products),storeyIDs=ids(types.IFCBUILDINGSTOREY,LIMIT.storeys),projectIDs=ids(types.IFCPROJECT,100);
    for(const id of [...productIDs,...storeyIDs,...projectIDs])read(id);
    const relationTypes=['IFCRELCONTAINEDINSPATIALSTRUCTURE','IFCRELAGGREGATES','IFCRELDEFINESBYPROPERTIES','IFCRELDEFINESBYTYPE','IFCRELASSOCIATESMATERIAL'];
    for(const name of relationTypes)for(const id of ids(types[name],LIMIT.records))read(id);
    const guids=new Map();for(const id of productIDs){const value=raw(records.get(id).fields.GlobalId);if(guidOK(value))guids.set(value,(guids.get(value)||0)+1)}
    const converted=new Set(),productSet=new Set(productIDs);
    function object(expressID){if(!productSet.has(expressID))throw Error('IFC mesh has no source product');const record=records.get(expressID),value=raw(record.fields.GlobalId),guid=typeof value==='string'?value:'';
      return {expressID,typeName:record.typeName,guid,guidStatus:value==null||value===''?'missing':!guidOK(value)?'malformed':guids.get(value)>1?'duplicate':'valid'};
    }
    return {object,markConverted(id){object(id);converted.add(id)},finish(){
      const products=productIDs.map(expressID=>({...object(expressID),represented:records.get(expressID).fields.Representation!=null,converted:converted.has(expressID)}));
      const storeys=storeyIDs.map(expressID=>{const fields=records.get(expressID).fields;return {expressID,name:raw(fields.Name)??'',elevation:raw(fields.Elevation)??null}});
      const summary={products:products.length,representedProducts:products.filter(p=>p.represented).length,convertedProducts:converted.size,unconvertedRepresentedProducts:products.filter(p=>p.represented&&!p.converted).length,storeys:storeys.length,records:records.size,malformedGUIDs:products.filter(p=>p.guidStatus==='malformed').length,missingGUIDs:products.filter(p=>p.guidStatus==='missing').length,duplicateGUIDs:products.filter(p=>p.guidStatus==='duplicate').length};
      const sidecar={version:1,converter:'web-ifc-0.0.72',sourceSchema:api.GetModelSchema(model),rawSourceValues:true,excludedForwardFields:[...omitted].sort(),products,storeys,records:[...records.values()].sort((a,b)=>a.expressID-b.expressID),summary};
      if(encoder.encode(JSON.stringify(sidecar)).length>LIMIT.bytes)throw Error('IFC property sidecar exceeds its byte budget');return sidecar;
    }};
  }
  root.IFCProperties={prepare,guidOK};
})(globalThis);
