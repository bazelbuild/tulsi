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

// Set of UTIs used by Xcode in project files. These can be extracted from *.pbfilespec specs within
// the Xcode bundle.
let FileExtensionToUTI = [
  "1": "text.man",
  "C": "sourcecode.cpp.cpp",
  "H": "sourcecode.cpp.h",
  "M": "sourcecode.cpp.objcpp",
  "a": "archive.ar",
  "ada": "sourcecode.ada",
  "adb": "sourcecode.ada",
  "ads": "sourcecode.ada",
  "aiff": "audio.aiff",
  "api": "text.woapi",
  "app": "wrapper.application",
  "asdictionary": "archive.asdictionary",
  "asm": "sourcecode.asm.asm",
  "au": "audio.au",
  "avi": "video.avi",
  "bin": "archive.macbinary",
  "bmp": "image.bmp",
  "bundle": "wrapper.plug-in",
  "bzl": "com.google.bazel.skylark",
  "c": "sourcecode.c.c",
  "c++": "sourcecode.cpp.cpp",
  "cc": "sourcecode.cpp.cpp",
  "cdda": "audio.aiff",
  "ci": "sourcecode.glsl",
  "cikernel": "sourcecode.glsl",
  "cl": "sourcecode.opencl",
  "class": "compiled.javaclass",
  "classdescription": "text.plist.ibClassDescription",
  "classdescriptions": "text.plist.ibClassDescription",
  "cp": "sourcecode.cpp.cpp",
  "cpp": "sourcecode.cpp.cpp",
  "csh": "text.script.csh",
  "css": "text.css",
  "cxx": "sourcecode.cpp.cpp",
  "d": "sourcecode.dtrace",
  "d2wmodel": "text.plist.d2wmodel",
  "dSYM": "wrapper.dsym",
  "defs": "sourcecode.mig",
  "dict": "text.plist",
  "dsym": "wrapper.dsym",
  "dtd": "text.xml",
  "dylan": "sourcecode.dylan",
  "dylib": "compiled.mach-o.dylib",
  "ear": "archive.ear",
  "exp": "sourcecode.exports",
  "f": "sourcecode.fortran",
  "f77": "sourcecode.fortran.f77",
  "f90": "sourcecode.fortran.f90",
  "f95": "sourcecode.fortran.f90",
  "for": "sourcecode.fortran",
  "frag": "sourcecode.glsl",
  "framework": "wrapper.framework",
  "fsh": "sourcecode.glsl",
  "gif": "image.gif",
  "gmk": "sourcecode.make",
  "gz": "archive.gzip",
  "h": "sourcecode.c.h",
  "h++": "sourcecode.cpp.h",
  "hh": "sourcecode.cpp.h",
  "hp": "sourcecode.cpp.h",
  "hpp": "sourcecode.cpp.h",
  "hqx": "archive.binhex",
  "htm": "text.html",
  "html": "text.html",
  "htmld": "wrapper.htmld",
  "hxx": "sourcecode.cpp.h",
  "i": "sourcecode.c.c.preprocessed",
  "icns": "image.icns",
  "ico": "image.ico",
  "ii": "sourcecode.cpp.cpp.preprocessed",
  "inc": "sourcecode.pascal",
  "jam": "sourcecode.jam",
  "jar": "archive.jar",
  "java": "sourcecode.java",
  "javascript": "sourcecode.javascript",
  "jobs": "sourcecode.jobs",
  "jpeg": "image.jpeg",
  "jpg": "image.jpeg",
  "js": "sourcecode.javascript",
  "jscript": "sourcecode.javascript",
  "jsp": "text.html.other",
  "kext": "wrapper.kernel-extension",
  "l": "sourcecode.lex",
  "lid": "sourcecode.dylan",
  "ll": "sourcecode.asm.llvm",
  "llx": "sourcecode.asm.llvm",
  "lm": "sourcecode.lex",
  "lmm": "sourcecode.lex",
  "lp": "sourcecode.lex",
  "lpp": "sourcecode.lex",
  "lxx": "sourcecode.lex",
  "m": "sourcecode.c.objc",
  "mak": "sourcecode.make",
  "mi": "sourcecode.c.objc.preprocessed",
  "mid": "audio.midi",
  "midi": "audio.midi",
  "mig": "sourcecode.mig",
  "mii": "sourcecode.cpp.objcpp.preprocessed",
  "mm": "sourcecode.cpp.objcpp",
  "moov": "video.quicktime",
  "mov": "video.quicktime",
  "mp3": "audio.mp3",
  "mpeg": "video.mpeg",
  "mpg": "video.mpeg",
  "mpkg": "wrapper.installer-mpkg",
  "nasm": "sourcecode.nasm",
  "nib": "wrapper.nib",
  "nib~": "wrapper.nib",
  "nqc": "sourcecode.nqc",
  "o": "compiled.mach-o.objfile",
  "p": "sourcecode.pascal",
  "pas": "sourcecode.pascal",
  "pbfilespec": "text.plist.pbfilespec",
  "pblangspec": "text.plist.pblangspec",
  "pbxproj": "text.pbxproject",
  "pch": "sourcecode.c.h",
  "pch++": "sourcecode.cpp.h",
  "pct": "image.pict",
  "pdf": "image.pdf",
  "perl": "text.script.perl",
  "php": "text.script.php",
  "php3": "text.script.php",
  "php4": "text.script.php",
  "phtml": "text.script.php",
  "pict": "image.pict",
  "pkg": "wrapper.installer-pkg",
  "pl": "text.script.perl",
  "playground": "file.playground",
  "plist": "text.plist",
  "pm": "text.script.perl",
  "png": "image.png",
  "pp": "sourcecode.pascal",
  "ppob": "archive.ppob",
  "proto": "public.protobuf-source",
  "py": "text.script.python",
  "qtz": "video.quartz-composer",
  "r": "sourcecode.rez",
  "rb": "text.script.ruby",
  "rbw": "text.script.ruby",
  "rcx": "compiled.rcx",
  "rez": "sourcecode.rez",
  "rhtml": "text.html.other",
  "rsrc": "archive.rsrc",
  "rtf": "text.rtf",
  "rtfd": "wrapper.rtfd",
  "s": "sourcecode.asm",
  "scriptSuite": "text.plist.scriptSuite",
  "scriptTerminology": "text.plist.scriptTerminology",
  "sh": "text.script.sh",
  "shtml": "text.html.other",
  "sit": "archive.stuffit",
  "storyboard": "file.storyboard",
  "storyboardc": "wrapper.storyboardc",
  "strings": "text.plist.strings",
  "swift": "sourcecode.swift",
  "tar": "archive.tar",
  "tcc": "sourcecode.cpp.cpp",
  "tif": "image.tiff",
  "tiff": "image.tiff",
  "txt": "text",
  "vert": "sourcecode.glsl",
  "view": "archive.rsrc",
  "vsh": "sourcecode.glsl",
  "war": "archive.war",
  "wav": "audio.wav",
  "woa": "wrapper.application.webobjects",
  "wod": "text.wodefinitions",
  "woo": "text.plist.woobjects",
  "worksheet": "text.script.worksheet",
  "wos": "sourcecode.webscript",
  "xcclassmodel": "wrapper.xcclassmodel",
  "xcconfig": "text.xcconfig",
  "xcdatamodel": "wrapper.xcdatamodel",
  "xcdatamodeld": "wrapper.xcdatamodeld",
  "xclangspec": "text.plist.xclangspec",
  "xcmappingmodel": "wrapper.xcmappingmodel",
  "xcode": "wrapper.pb-project",
  "xcodeproj": "wrapper.pb-project",
  "xconf": "text.xml",
  "xcplaygroundpage": "file.xcplaygroundpage",
  "xcspec": "text.plist.xcspec",
  "xcsynspec": "text.plist.xcsynspec",
  "xctarget": "wrapper.pb-target",
  "xctxtmacro": "text.plist.xctxtmacro",
  "xhtml": "text.xml",
  "xib": "file.xib",
  "xmap": "text.xml",
  "xml": "text.xml",
  "xsl": "text.xml",
  "xslt": "text.xml",
  "xsp": "text.xml",
  "y": "sourcecode.yacc",
  "ym": "sourcecode.yacc",
  "ymm": "sourcecode.yacc",
  "yp": "sourcecode.yacc",
  "ypp": "sourcecode.yacc",
  "yxx": "sourcecode.yacc",
  "zip": "archive.zip",
]

// Set of UTIs used by Xcode for source or target bundle directories in project files.
// Note that entries here may be duplicative with the FileExtensionToUTI dictionary above.
let DirExtensionToUTI = [
  "app": "wrapper.application",
  "appex": "wrapper.app-extension",
  "bundle": "wrapper.plug-in",
  "framework": "wrapper.framework",
  "octest": "wrapper.cfbundle",
  "xcassets": "folder.assetcatalog",
  "xcodeproj": "wrapper.pb-project",
  "xcdatamodel": "wrapper.xcdatamodel",
  "xcdatamodeld": "wrapper.xcdatamodeld",
  "xcmappingmodel": "wrapper.xcmappingmodel",
  "xctest": "wrapper.cfbundle",
  "xcstickers": "folder.stickers",
  "xpc": "wrapper.xpc-service",
]

// Helper methods to extract filename-like substrings from strings.
extension String {
  var pbPathExtension: String? {
    let ext = (self as NSString).pathExtension
    if ext.isEmpty {
      return nil
    }
    return ext
  }

  var pbPathUTI: String? {
    guard let ext = pbPathExtension else {
      return nil
    }
    let lcaseExt = ext.lowercased()
    if let uti = FileExtensionToUTI[lcaseExt] {
      return uti
    }
    if let uti = DirExtensionToUTI[lcaseExt] {
      return uti
    }

    // Fall back to the system UTI if there's no Xcode-specific override.
    guard let unmanaged = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext as CFString, nil) else {
      return nil
    }
    let managed = unmanaged.takeRetainedValue()
    return managed as String
  }

  var pbPathLastComponent: String {
    return (self as NSString).lastPathComponent
  }
}
