// Copyright 2016 The Tulsi Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

typealias PBXDict = Dictionary<String, NSObject>
let XcodeProjectArchiveVersion = "1"


protocol PBXProjSerializable: class {
  func serializeInto(serializer: PBXProjFieldSerializer) throws
}


/// Methods for serializing components of a PBXObject.
protocol PBXProjFieldSerializer {
  func addField(name: String, _ obj: PBXObjectProtocol?, rawID: Bool) throws
  func addField(name: String, _ val: Int) throws
  func addField(name: String, _ val: Bool) throws
  func addField(name: String, _ val: String?) throws
  func addField(name: String, _ val: [String: AnyObject]?) throws
  func addField<T: PBXObjectProtocol>(name: String, _ values: [T]) throws
  func addField(name: String, _ values: [String]) throws

  // Serializes an object if it has not already been serialized and returns its globalID, optionally
  // with a comment string attached unless returnRawID is true.
  func serializeObject(object: PBXObjectProtocol, returnRawID: Bool) throws -> String
}

extension PBXProjFieldSerializer {
  func addField(name: String, _ obj: PBXObjectProtocol?) throws {
    try addField(name, obj, rawID: false)
  }
}


private extension NSMutableData {
  enum EncodingError: ErrorType {
    // A string failed to be encoded into NSData as UTF8.
    case StringUTF8EncodingError
  }

  func tulsi_appendString(str: String) throws {
    guard let encoded = str.dataUsingEncoding(NSUTF8StringEncoding) else {
      throw EncodingError.StringUTF8EncodingError
    }
    self.appendData(encoded)
  }
}


/// Encapsulates the ability to serialize a PBXProject and its contents.
class PBXProjSerializer {
  /// The root PBXProject containing all other objects.
  let rootObject: PBXProject

  private let gidGenerator: GIDGeneratorProtocol

  init(rootObject: PBXProject, gidGenerator: GIDGeneratorProtocol) {
    self.rootObject = rootObject
    self.gidGenerator = gidGenerator
  }

  /// Serializes the project into a Dictionary object. Setting forceBasicTypes will convert any
  /// integers or booleans to be stored as Strings.
  func toDictionary(forceBasicTypes forceBasicTypes: Bool = false) -> PBXDict {
    let serializer = DictionarySerializer(rootObject: rootObject,
                                          gidGenerator: gidGenerator,
                                          forceBasicTypes: forceBasicTypes)
    return serializer.serialize()
  }

  /// Serializes to an XML formatted plist. Setting forceBasicTypes will convert any integers or
  /// booleans to be stored as Strings.
  func toXML(forceBasicTypes forceBasicTypes: Bool = false) -> NSData? {
    let dict = toDictionary(forceBasicTypes: forceBasicTypes)

    do {
      return try NSPropertyListSerialization.dataWithPropertyList(dict, format: .XMLFormat_v1_0, options: 0)
    } catch let error as NSError {
      // TODO(abaire): this probably indicates a programming error but it'd be good to get it into a
      //               crash log in case it happens outside of a development environment.
      print(error.localizedDescription)
      print(dict)
      return nil
    }
  }

  /// Serializes to an OpenStep formatted plist (like an Xcode-generated project file).
  func toOpenStep() -> NSData? {
    let serializer = OpenStepSerializer(rootObject: rootObject, gidGenerator: gidGenerator)
    return serializer.serialize()
  }
}


/// Encapsulates the ability to serialize a PBXProject into a dictionary.
class DictionarySerializer: PBXProjFieldSerializer {
  var dict: PBXDict

  private let rootObject: PBXProject
  private let gidGenerator: GIDGeneratorProtocol
  private let forceBasicTypes: Bool

  // Map of globalIDs to all PBXObjectProtocol instances contained in this project.
  private var objects = [String: PBXDict]()

  // The object currently being serialized; XcodeProjFieldSerializer methods act on this object.
  private var currentObject: PBXDict {
    get {
      return objects[currentObjectID]!
    }
    set {
      objects[currentObjectID] = newValue
    }
  }
  private var currentObjectID: String! = nil

  init(rootObject: PBXProject, gidGenerator: GIDGeneratorProtocol, forceBasicTypes: Bool) {
    self.rootObject = rootObject
    self.gidGenerator = gidGenerator
    self.forceBasicTypes = forceBasicTypes
    dict = PBXDict()
    dict["archiveVersion"] = XcodeProjectArchiveVersion
    dict["classes"] = PBXDict();
    dict["objectVersion"] = XcodeVersionInfo.objectVersion
  }

  func serialize() -> PBXDict {
    let rootObjectID = serializeObject(rootObject)
    dict["objects"] = objects
    dict["rootObject"] = rootObjectID
    return dict
  }

  // MARK: - XcodeProjFieldSerializer

  func serializeObject(obj: PBXObjectProtocol, returnRawID: Bool = false) -> String {
    if objects[obj.globalID] != nil {
      return obj.globalID
    }
    // If the object already has a GID from a previous serialization, reuse it.
    if obj.globalID.isEmpty {
      obj.globalID = gidGenerator.generate(obj)
    }

    let stack = currentObjectID
    defer { currentObjectID = stack }

    objects[obj.globalID] = PBXDict()
    currentObjectID = obj.globalID
    currentObject["isa"] = obj.isa
    try! obj.serializeInto(self)

    return obj.globalID
  }

  func addField(name: String, _ obj: PBXObjectProtocol?, rawID: Bool) {
    guard let local = obj else {
      return
    }

    let gid = serializeObject(local)
    currentObject[name] = gid
  }

  func addField(name: String, _ val: Int) {
    if forceBasicTypes {
      currentObject[name] = "\(val)"
    } else {
      currentObject[name] = NSNumber(integer: val)
    }
  }

  func addField(name: String, _ val: Bool) {
    if forceBasicTypes {
      let intVal = val ? 1 : 0
      currentObject[name] = "\(intVal)"
    } else {
      currentObject[name] = NSNumber(bool: val)
    }
  }

  func addField(name: String, _ val: String?) {
    if let local = val {
      currentObject[name] = local
    }
  }

  func addField(name: String, _ val: [String: AnyObject]?) {
    if let local = val {
      currentObject[name] = local
    }
  }

  func addField<T: PBXObjectProtocol>(name: String, _ values: [T]) {
    var array = [String]()
    for val in values {
      let gid = serializeObject(val)
      array.append(gid)
    }
    currentObject[name] = array
  }

  func addField(name: String, _ values: [String]) {
    currentObject[name] = values
  }
}


/// Encapsulates the ability to serialize a PBXProject into an OpenStep formatted plist.
final class OpenStepSerializer: PBXProjFieldSerializer {

  private enum SerializationError: ErrorType {
    // A PBX object was referenced but never defined.
    case ReferencedObjectNotFoundError
  }

  // List of objects that are always serialized on a single line by Xcode.
  private static let CompactPBXTypes = Set<String>(["PBXBuildFile", "PBXFileReference"])

  private let rootObject: PBXProject
  private let gidGenerator: GIDGeneratorProtocol
  private var objects = [String: TypedDict]()

  // Maps PBXObject types to arrays of keys in the objects array. This allows serialization in the
  // same OpenStep format as Xcode.
  private var typedObjectIndex = [String: [String]]()

  // Dictionary containing data for the object currently being serialized.
  private var currentDict: RawDict!

  // Regex used to determine whether a string value can be printed without quotes or not.
  private let unquotedSerializableStringRegex = try! NSRegularExpression(pattern: "^[A-Z0-9._/]+$", options: [.CaseInsensitive])


  init(rootObject: PBXProject, gidGenerator: GIDGeneratorProtocol) {
    self.rootObject = rootObject
    self.gidGenerator = gidGenerator
  }

  func serialize() -> NSData? {
    do {
      let rootObjectID = try serializeObject(rootObject)
      return serializeObjectDictionaryWithRoot(rootObjectID)
    } catch {
      return nil
    }
  }

  // MARK: - XcodeProjFieldSerializer

  func serializeObject(obj: PBXObjectProtocol, returnRawID: Bool = false) throws -> String {
    if let typedObject = objects[obj.globalID] {
      if !returnRawID {
        return "\(obj.globalID)\(typedObject.comment)"
      }
      return obj.globalID
    }

    // If the object doesn't have a GID from a previous serialization, generate one.
    if obj.globalID.isEmpty {
      obj.globalID = gidGenerator.generate(obj)
    }

    let globalID = obj.globalID
    let isa = obj.isa
    let serializationDict = TypedDict(gid: globalID, isa: isa, comment: obj.comment)
    let stack = currentDict
    currentDict = serializationDict

    // Note: The object must be added to the objects dictionary prior to serialization in order to
    // allow recursive references. e.g., PBXTargetDependency instances between targets in the same
    // PBXProject instance.
    objects[globalID] = serializationDict

    try obj.serializeInto(self)

    if typedObjectIndex[isa] == nil {
      typedObjectIndex[isa] = [globalID]
    } else {
      typedObjectIndex[isa]!.append(globalID)
    }

    currentDict = stack

    if returnRawID {
      return globalID
    }
    return "\(globalID)\(serializationDict.comment)"
  }

  func addField(name: String, _ obj: PBXObjectProtocol?, rawID: Bool) throws {
    guard let local = obj else {
      return
    }

    let gid = try serializeObject(local, returnRawID: rawID)
    currentDict.dict[name] = gid
  }

  func addField(name: String, _ val: Int) throws {
    currentDict.dict[name] = val
  }

  func addField(name: String, _ val: Bool) throws {
    let intVal = val ? 1 : 0
    currentDict.dict[name] = intVal
  }

  func addField(name: String, _ val: String?) throws {
    guard let stringValue = val else {
      return
    }

    currentDict.dict[name] = escapeString(stringValue)
  }

  func addField(name: String, _ val: [String: AnyObject]?) throws {
    // Note: Xcode will crash if empty buildSettings member dictionaries of XCBuildConfiguration's
    // are omitted so this does not check to see if the dictionary is empty or not.
    guard let dict = val else {
      return
    }

    let stack = currentDict
    currentDict = RawDict()
    for (key, value) in dict {
      if let stringValue = value as? String {
        currentDict.dict[key] = escapeString(stringValue)
      } else if let dictValue = value as? [String: AnyObject] {
        try addField(key, dictValue)
      } else if let arrayValue = value as? [String] {
        try addField(key, arrayValue)
      } else {
        assertionFailure("Unsupported complex object \(value) in nested dictionary type")
      }
    }
    stack.dict[name] = currentDict
    currentDict = stack

  }

  func addField<T: PBXObjectProtocol>(name: String, _ values: [T]) throws {
    currentDict.dict[name] = try values.map() { try serializeObject($0) }
  }

  func addField(name: String, _ values: [String]) throws {
    currentDict.dict[name] = values.map() { escapeString($0) }
  }

  func getGlobalIDForObject(object: PBXObjectProtocol) throws -> String {
    return try serializeObject(object)
  }

  // MARK: - Private methods

  private func serializeObjectDictionaryWithRoot(rootObjectID: String) -> NSData? {
    let data = NSMutableData()
    do {
      try data.tulsi_appendString("// !$*UTF8*$!\n{\n")
      var indent = "\t"

      func appendIndentedString(value: String) throws {
        try data.tulsi_appendString(indent + value)
      }

      try appendIndentedString("archiveVersion = \(XcodeProjectArchiveVersion);\n")
      try appendIndentedString("classes = {\n\(indent)};\n")
      try appendIndentedString("objectVersion = \(XcodeVersionInfo.objectVersion);\n")

      try appendIndentedString("objects = {\n")
      let oldIndent = indent
      indent += "\t"

      try encodeSerializedPBXObjectArray("PBXBuildFile", into: data, indented: indent)
      try encodeSerializedPBXObjectArray("PBXContainerItemProxy", into: data, indented: indent)
      try encodeSerializedPBXObjectArray("PBXFileReference", into: data, indented: indent)
      try encodeSerializedPBXObjectArray("PBXGroup", into: data, indented: indent)
      try encodeSerializedPBXObjectArray("PBXLegacyTarget", into: data, indented: indent)
      try encodeSerializedPBXObjectArray("PBXNativeTarget", into: data, indented: indent)
      try encodeSerializedPBXObjectArray("PBXProject", into: data, indented: indent)
      try encodeSerializedPBXObjectArray("PBXShellScriptBuildPhase", into: data, indented: indent)
      try encodeSerializedPBXObjectArray("PBXSourcesBuildPhase", into: data, indented: indent)
      try encodeSerializedPBXObjectArray("PBXTargetDependency", into: data, indented: indent)
      try encodeSerializedPBXObjectArray("XCBuildConfiguration", into: data, indented: indent)
      try encodeSerializedPBXObjectArray("XCConfigurationList", into: data, indented: indent)
      try encodeSerializedPBXObjectArray("XCVersionGroup", into: data, indented: indent)

      assert(typedObjectIndex.isEmpty, "Failed to encode objects of type(s) \(typedObjectIndex.keys)")

      indent = oldIndent
      try appendIndentedString("};\n")
      try appendIndentedString("rootObject = \(rootObjectID);\n")
      try data.tulsi_appendString("}")
    } catch {
      return nil
    }

    return data
  }

  private func encodeSerializedPBXObjectArray(key: String,
                                              into data: NSMutableData,
                                              indented indent: String) throws {
    guard let entries = typedObjectIndex[key] else {
      return
    }

    // For debugging purposes, throw away the index now that it's being encoded.
    typedObjectIndex.removeValueForKey(key)

    try data.tulsi_appendString("\n/* Begin \(key) section */\n")

    for gid in entries.sort() {
      guard let obj = objects[gid] else {
        throw SerializationError.ReferencedObjectNotFoundError
      }

      try obj.appendToData(data, indent: indent)
    }

    try data.tulsi_appendString("/* End \(key) section */\n")
  }

  private func escapeString(val: String) -> String {
    var val = val
    // The quotation marks can be omitted if the string is composed strictly of alphanumeric
    // characters and contains no white space (numbers are handled as strings in property lists).
    // Though the property list format uses ASCII for strings, note that Cocoa uses Unicode. Since
    // string encodings vary from region to region, this representation makes the format fragile.
    // You may see strings containing unreadable sequences of ASCII characters; these are used to
    // represent Unicode characters.
    let valueRange = NSMakeRange(0, val.characters.count)
    if unquotedSerializableStringRegex.firstMatchInString(val, options: NSMatchingOptions.Anchored, range: valueRange) != nil {
      return val
    } else {
      val = val.stringByReplacingOccurrencesOfString("\\", withString: "\\\\")
      val = val.stringByReplacingOccurrencesOfString("\"", withString: "\\\"")
      val = val.stringByReplacingOccurrencesOfString("\n", withString: "\\n")
      return "\"\(val)\""
    }
  }


  /// Intermediate representation of a raw dictionary.
  private class RawDict {
    var dict = [String: AnyObject]()
    let compact: Bool

    init(compact: Bool = false) {
      self.compact = compact
    }

    func appendToData(data: NSMutableData, indent: String) throws {
      try data.tulsi_appendString("{")

      let (closingSpacer, spacer) = spacersForIndent(indent)
      if !compact {
        try data.tulsi_appendString(spacer)
      }

      try appendContentsToData(data, indent: indent, spacer: spacer)
      try data.tulsi_appendString("\(closingSpacer)};")
    }

    // MARK: - Internal methods

    func appendContentsToData(data: NSMutableData, indent: String, spacer: String) throws {
      let newIndent = indent + "\t"
      var leadingSpacer = ""
      for (key, value) in dict.sort({ $0.0 < $1.0 }) {
        if let rawDictValue = value as? RawDict {
          try data.tulsi_appendString("\(leadingSpacer)\(key) = ")
          try rawDictValue.appendToData(data, indent: newIndent)
        } else if let arrayValue = value as? [String] {
          try data.tulsi_appendString("\(leadingSpacer)\(key) = (")
          let itemSpacer = spacer + (compact ? "" : "\t")
          try arrayValue.forEach() { try data.tulsi_appendString("\(itemSpacer)\($0),") }
          try data.tulsi_appendString("\(spacer));")
        } else {
          try data.tulsi_appendString("\(leadingSpacer)\(key) = \(value);")
        }
        leadingSpacer = spacer
      }
    }

    func spacersForIndent(indent: String) -> (String, String) {
      let closingSpacer: String
      let spacer: String
      if compact {
        spacer = " "
        closingSpacer = spacer
      } else {
        closingSpacer = "\n\(indent)"
        spacer = "\(closingSpacer)\t"
      }
      return (closingSpacer, spacer)
    }
  }


  /// Intermediate representation of a typed PBXObject.
  private final class TypedDict: RawDict {
    let gid: String
    let isa: String
    let comment: String

    init(gid: String, isa: String, comment: String? = nil) {
      self.gid = gid
      self.isa = isa
      if let comment = comment {
        self.comment = " /* \(comment) */"
      } else {
        self.comment = ""
      }
      super.init(compact: OpenStepSerializer.CompactPBXTypes.contains(isa))
    }

    override func appendToData(data: NSMutableData, indent: String) throws {
      try data.tulsi_appendString("\(indent)\(gid)\(comment) = {")

      let (closingSpacer, spacer) = spacersForIndent(indent)
      if !compact {
        try data.tulsi_appendString(spacer)
      }

      try data.tulsi_appendString("isa = \(isa);\(spacer)")
      try appendContentsToData(data, indent: indent, spacer: spacer)
      try data.tulsi_appendString("\(closingSpacer)};\n")
    }
  }
}
