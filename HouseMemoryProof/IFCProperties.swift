import Foundation
import CoreFoundation
import CryptoKit

struct IFCObjectReference:Codable,Equatable {
  var expressID:Int;var typeName:String;var guid:String;var guidStatus:String
  static func guidValid(_ value:String)->Bool {value.range(of:"^[0-3][0-9A-Za-z_$]{21}$",options:.regularExpression) != nil}
  var valid:Bool {
    expressID>0 && expressID<=Int(Int32.max) && !typeName.isEmpty && IFCCoordinateReference.bounded(typeName) && IFCCoordinateReference.bounded(guid) && ["valid","duplicate","malformed","missing"].contains(guidStatus) && (!["valid","duplicate"].contains(guidStatus) || Self.guidValid(guid)) && (guidStatus != "missing" || guid.isEmpty)
  }
}
struct IFCPropertySummary:Codable,Equatable {
  var products:Int;var representedProducts:Int;var convertedProducts:Int;var unconvertedRepresentedProducts:Int
  var storeys:Int;var records:Int;var malformedGUIDs:Int;var missingGUIDs:Int;var duplicateGUIDs:Int
  var valid:Bool {
    (0...10000).contains(products) && (0...products).contains(representedProducts) && (0...products).contains(convertedProducts) && (0...representedProducts).contains(unconvertedRepresentedProducts) && (0...100).contains(storeys) && (products...20000).contains(records) && [malformedGUIDs,missingGUIDs,duplicateGUIDs].allSatisfy{(0...products).contains($0)} && malformedGUIDs+missingGUIDs+duplicateGUIDs<=products
  }
  var description:String {
    "Converted \(convertedProducts) of \(representedProducts) products with representations; \(unconvertedRepresentedProducts) were not emitted as meshes. \(storeys) storeys and \(records) source records retained. GUID warnings: \(missingGUIDs) missing, \(malformedGUIDs) malformed, \(duplicateGUIDs) duplicate. Source properties use original units; storeys are not assigned to house levels."
  }
}
struct IFCPropertyReference:Codable,Equatable {
  var asset:String;var sourceSHA256:String;var summary:IFCPropertySummary
  var valid:Bool {asset.range(of:"^[0-9a-f]{64}\\.json$",options:.regularExpression) != nil && sourceSHA256.range(of:"^[0-9a-f]{64}$",options:.regularExpression) != nil && summary.valid}
}

// The JSON graph is a bounded documentary sidecar, not an editable IFC model.
// It retains raw scalar units and references; geometry/owner graphs remain in
// the immutable original. Identity is source hash + EXPRESS ID, never GUID alone.
enum IFCProperties {
  struct Verified {
    var data:Data;var sourceSHA256:String;var sourceSchema:String;var summary:IFCPropertySummary;var objects:[Int:IFCObjectReference];var converted:Set<Int>
    #if canImport(UIKit)
    func store(in repo:Repository)throws->IFCPropertyReference {IFCPropertyReference(asset:try repo.put(data,ext:"json"),sourceSHA256:sourceSHA256,summary:summary)}
    #endif
    func matches(_ features:[Feature])->Bool {
      let refs=features.compactMap{$0.ifcObject}
      return refs.count==features.count && Set(refs.map{$0.expressID})==converted && refs.allSatisfy{objects[$0.expressID]==$0}
    }
  }
  static func require(_ condition:Bool,_ message:String)throws {if !condition {throw HouseError.message("IFC properties: "+message+". Original source remains preserved.")}}
  static func integer(_ value:Any?)->Int? {
    guard let number=value as? NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID(),number.doubleValue.isFinite,number.doubleValue.rounded()==number.doubleValue,abs(number.doubleValue)<=Double(Int32.max) else{return nil}
    return number.intValue
  }
  static func boolean(_ value:Any?)->Bool? {guard let number=value as? NSNumber,CFGetTypeID(number)==CFBooleanGetTypeID() else{return nil};return number.boolValue}
  static func scalar(_ value:Any?)->Any? {if let wrapped=value as? [String:Any],let value=wrapped["value"] {return value is NSNull ? nil:value};return value is NSNull ? nil:value}
  static func decode(_ raw:Any,sourceSHA256:String)throws->Verified {
    try require(sourceSHA256.range(of:"^[0-9a-f]{64}$",options:.regularExpression) != nil,"invalid original checksum")
    // Validate before serialization, bounding both recursion and bridge memory.
    var pending:[(Any,Int)]=[(raw,0)],values=0,textBytes=0
    while let (value,depth)=pending.popLast() {
      values+=1;try require(values<=250000 && depth<=22,"value or nesting limit exceeded")
      if let text=value as? String {try require(IFCCoordinateReference.bounded(text),"text limit exceeded");textBytes+=text.utf8.count;try require(textBytes<=4_000_000,"text byte limit exceeded")}
      else if let list=value as? [Any] {try require(list.count<=20000,"list limit exceeded");pending += list.map{($0,depth+1)}}
      else if let object=value as? [String:Any] {try require(object.count<=2000,"field limit exceeded");for (key,item) in object {pending.append((key,depth+1));pending.append((item,depth+1))}}
      else if let number=value as? NSNumber {try require(number.doubleValue.isFinite,"nonfinite number")}
      else {try require(value is NSNull,"unsupported value")}
    }
    guard var root=raw as? [String:Any],let records=root["records"] as? [[String:Any]],let products=root["products"] as? [[String:Any]],let storeys=root["storeys"] as? [[String:Any]] else{throw HouseError.message("IFC property inventory is missing.")}
    try require(integer(root["version"])==1 && root["converter"] as? String=="web-ifc-0.0.72" && boolean(root["rawSourceValues"])==true,"unsupported conversion format")
    try require((root["sourceSchema"] as? String)?.isEmpty==false && root["excludedForwardFields"] as? [String]==["OwnerHistory","Representation","RepresentationMaps"],"missing source semantics")
    if let stored=root["sourceSHA256"] {try require(stored as? String==sourceSHA256,"original checksum changed")}
    try require(products.count<=10000 && storeys.count<=100 && records.count<=20000,"inventory limit exceeded")
    var rows:[Int:[String:Any]]=[:],names:[Int:String]=[:]
    for record in records {
      guard let id=integer(record["expressID"]),id>0,let fields=record["fields"] as? [String:Any],let name=record["typeName"] as? String,!name.isEmpty else{throw HouseError.message("IFC property record is malformed.")}
      try require(rows[id]==nil,"repeated record identity");rows[id]=fields;names[id]=name
    }
    for fields in rows.values {for (key,value) in fields where !["OwnerHistory","Representation","RepresentationMaps"].contains(key) {
      var references=[value]
      while let value=references.popLast() {
        if let object=value as? [String:Any] {
          if integer(object["type"])==5 {guard let id=integer(object["value"]),rows[id] != nil else{throw HouseError.message("IFC property graph has a missing reference.")}}
          else {references += Array(object.values)}
        } else if let list=value as? [Any] {references += list}
      }
    }}
    var objects:[Int:IFCObjectReference]=[:],converted=Set<Int>(),represented=Set<Int>(),guidCounts:[String:Int]=[:]
    for product in products {
      let object=try JSONDecoder().decode(IFCObjectReference.self,from:JSONSerialization.data(withJSONObject:product))
      try require(object.valid && objects[object.expressID]==nil && rows[object.expressID] != nil && names[object.expressID]==object.typeName,"invalid product identity")
      guard let emitted=boolean(product["converted"]),let hasRepresentation=boolean(product["represented"]) else{throw HouseError.message("IFC conversion coverage is missing.")}
      let fields=rows[object.expressID]!,rawGUID=scalar(fields["GlobalId"]),guid=rawGUID as? String ?? ""
      try require(guid==object.guid,"GUID differs from original record")
      let originalRepresentation=fields["Representation"] != nil && !(fields["Representation"] is NSNull)
      try require(hasRepresentation==originalRepresentation,"representation inventory differs")
      if hasRepresentation {represented.insert(object.expressID)}
      if emitted {converted.insert(object.expressID)}
      if IFCObjectReference.guidValid(guid) {guidCounts[guid,default:0]+=1}
      objects[object.expressID]=object
    }
    for object in objects.values {
      let value=scalar(rows[object.expressID]!["GlobalId"])
      let expected=value==nil || (value as? String)=="" ? "missing":!IFCObjectReference.guidValid(object.guid) ? "malformed":guidCounts[object.guid,default:0]>1 ? "duplicate":"valid"
      try require(object.guidStatus==expected,"GUID warning differs from source")
    }
    var seenStoreys=Set<Int>()
    for storey in storeys {
      guard let id=integer(storey["expressID"]),let fields=rows[id],let name=storey["name"] as? String else{throw HouseError.message("IFC storey inventory is malformed.")}
      try require(seenStoreys.insert(id).inserted && objects[id] != nil && name==(scalar(fields["Name"]) as? String ?? ""),"storey identity differs")
      let elevation=scalar(fields["Elevation"]),saved=scalar(storey["elevation"])
      if let elevation {guard let number=elevation as? NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID(),let stored=saved as? NSNumber,CFGetTypeID(stored) != CFBooleanGetTypeID(),number==stored else{throw HouseError.message("IFC storey elevation differs from raw source units.")}}
      else {try require(saved==nil,"storey elevation differs from raw units")}
    }
    let summary=IFCPropertySummary(products:products.count,representedProducts:represented.count,convertedProducts:converted.count,unconvertedRepresentedProducts:represented.subtracting(converted).count,storeys:storeys.count,records:records.count,malformedGUIDs:objects.values.filter{$0.guidStatus=="malformed"}.count,missingGUIDs:objects.values.filter{$0.guidStatus=="missing"}.count,duplicateGUIDs:objects.values.filter{$0.guidStatus=="duplicate"}.count)
    guard let provided=root["summary"] else{throw HouseError.message("IFC property summary is missing.")}
    let claimed=try JSONDecoder().decode(IFCPropertySummary.self,from:JSONSerialization.data(withJSONObject:provided))
    try require(summary.valid && summary==claimed,"conversion totals disagree")
    root["sourceSHA256"]=sourceSHA256
    let data=try JSONSerialization.data(withJSONObject:root,options:.sortedKeys)
    try require(data.count<=4_000_000,"sidecar byte limit exceeded")
    return Verified(data:data,sourceSHA256:sourceSHA256,sourceSchema:root["sourceSchema"] as! String,summary:summary,objects:objects,converted:converted)
  }
  #if canImport(UIKit)
  static func read(_ reference:IFCPropertyReference,repo:Repository)throws->Verified {
    try require(reference.valid,"invalid saved reference")
    guard let raw=try JSONSerialization.jsonObject(with:repo.read(reference.asset,limit:4_000_000)) as? [String:Any],raw["sourceSHA256"] as? String==reference.sourceSHA256 else{throw HouseError.message("IFC property sidecar has lost its original source checksum.")}
    let decoded=try decode(raw,sourceSHA256:reference.sourceSHA256)
    try require(decoded.summary==reference.summary,"saved totals changed");return decoded
  }
  #endif
}
