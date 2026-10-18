/* Source-frame bookkeeping only. No CRS or house registration is applied. */
(function(root){
  'use strict';
  const text=v=>{v=v?.value ?? v;if(typeof v!=='string')return '';if(v.length>4096||v.includes('\0')||new TextEncoder().encode(v).length>4096)throw Error('IFC coordinate metadata exceeds its text budget');return v};
  const number=v=>{v=v?.value ?? v;if(typeof v!=='number')return null;if(!Number.isFinite(v)||Math.abs(v)>1e12)throw Error('IFC coordinate metadata exceeds its numeric budget');return v};
  const ids=(api,id,type)=>{if(typeof type!=='number')return [];const rows=api.GetLineIDsWithType(id,type,true);if(rows.size()>100000)throw Error('IFC metadata exceeds its admission limit');return Array.from({length:rows.size()},(_,i)=>rows.get(i))};
  const read=(api,id,ref)=>ref?.value?api.GetLine(id,ref.value,false):null;
  function metadata(api,id,types){
    const maps=ids(api,id,types.IFCMAPCONVERSION);
    if(maps.length>16)throw Error('IFC has too many coordinate conversions');
    let sourceLengthUnit='';
    for(const projectID of ids(api,id,types.IFCPROJECT)){
      const project=api.GetLine(id,projectID,false),units=read(api,id,project.UnitsInContext);
      for(const ref of units?.Units||[]){const unit=read(api,id,ref);if(text(unit?.UnitType)==='LENGTHUNIT')sourceLengthUnit=[text(unit?.Prefix),text(unit?.Name)].filter(Boolean).join(' ')}
    }
    return {version:1,converter:'web-ifc-0.0.72',sourceSchema:api.GetModelSchema(id),sourceLengthUnit,originMetres:{x:0,y:0,z:0},mapConversions:maps.map(expressID=>{
      const line=api.GetLine(id,expressID,false),target=read(api,id,line.TargetCRS),unit=read(api,id,target?.MapUnit),values={},targetCRS={};
      for(const key of ['Eastings','Northings','OrthogonalHeight','XAxisAbscissa','XAxisOrdinate','Scale','FactorX','FactorY','FactorZ']){const value=number(line[key]);if(value!==null)values[key]=value}
      for(const key of ['Name','Description','GeodeticDatum','VerticalDatum','MapProjection','MapZone']){const value=text(target?.[key]);if(value)targetCRS[key]=value}
      const mapUnit=[text(unit?.Prefix),text(unit?.Name)].filter(Boolean).join(' ');if(mapUnit)targetCRS.MapUnit=mapUnit;
      return {expressID,values,targetCRS};
    })};
  }
  function frame(reference){
    let chosen=false,origin=[0,0,0];
    return {point(p){
      if(p.length!==3||!p.every(v=>Number.isFinite(v)&&Math.abs(v)<=1e9))throw Error('IFC source coordinates exceed the supported range');
      if(!chosen){if(p.some(v=>Math.abs(v)>10000))origin=p.map(v=>Math.round(v/100)*100);chosen=true;reference.originMetres={x:origin[0],y:-origin[2],z:origin[1]}}
      const local=p.map((v,i)=>v-origin[i]);
      if(local.some(v=>Math.abs(v)>100000))throw Error('IFC extent exceeds the supported local range');
      return local;
    }};
  }
  root.IFCCoordinates={metadata,frame};
})(globalThis);
