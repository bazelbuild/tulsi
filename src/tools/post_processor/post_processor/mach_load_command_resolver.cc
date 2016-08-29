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

#include "mach_load_command_resolver.h"

#include <mach-o/loader.h>

namespace post_processor {

MachLoadCommandResolver::MachLoadCommandResolver() {
  command_to_info_[LC_SEGMENT] =
      "LC_SEGMENT * segment of this file to be mapped";
  command_to_info_[LC_SYMTAB] = "LC_SYMTAB * link-edit stab symbol table info";
  command_to_info_[LC_SYMSEG] =
      "LC_SYMSEG * link-edit gdb symbol table info (obsolete)";
  command_to_info_[LC_THREAD] = "LC_THREAD * thread";
  command_to_info_[LC_UNIXTHREAD] =
      "LC_UNIXTHREAD * unix thread (includes a stack)";
  command_to_info_[LC_LOADFVMLIB] =
      "LC_LOADFVMLIB * load a specified fixed VM shared library";
  command_to_info_[LC_IDFVMLIB] =
      "LC_IDFVMLIB * fixed VM shared library identification";
  command_to_info_[LC_IDENT] =
      "LC_IDENT * object identification info (obsolete)";
  command_to_info_[LC_FVMFILE] =
      "LC_FVMFILE * fixed VM file inclusion (internal use)";
  command_to_info_[LC_PREPAGE] =
      "LC_PREPAGE * prepage command (internal use)";
  command_to_info_[LC_DYSYMTAB] =
      "LC_DYSYMTAB * dynamic link-edit symbol table info";
  command_to_info_[LC_LOAD_DYLIB] =
      "LC_LOAD_DYLIB * load a dynamically linked shared library";
  command_to_info_[LC_ID_DYLIB] =
      "LC_ID_DYLIB * dynamically linked shared lib ident";
  command_to_info_[LC_LOAD_DYLINKER] =
      "LC_LOAD_DYLINKER * load a dynamic linker";
  command_to_info_[LC_ID_DYLINKER] =
      "LC_ID_DYLINKER * dynamic linker identification";
  command_to_info_[LC_PREBOUND_DYLIB] =
      "LC_PREBOUND_DYLIB * modules prebound for a dynamically";

  command_to_info_[LC_ROUTINES] = "LC_ROUTINES * image routines";
  command_to_info_[LC_SUB_FRAMEWORK] = "LC_SUB_FRAMEWORK * sub framework";
  command_to_info_[LC_SUB_UMBRELLA] = "LC_SUB_UMBRELLA * sub umbrella";
  command_to_info_[LC_SUB_CLIENT] = "LC_SUB_CLIENT * sub client";
  command_to_info_[LC_SUB_LIBRARY] = "LC_SUB_LIBRARY * sub library";
  command_to_info_[LC_TWOLEVEL_HINTS] =
      "LC_TWOLEVEL_HINTS * two-level namespace lookup hints";
  command_to_info_[LC_PREBIND_CKSUM] = "LC_PREBIND_CKSUM * prebind checksum";


  command_to_info_[LC_SEGMENT_64] =
      "LC_SEGMENT_64 * 64-bit segment of this file to be mapped";
  command_to_info_[LC_ROUTINES_64] = "LC_ROUTINES_64 * 64-bit image routines";
  command_to_info_[LC_UUID] = "LC_UUID * the uuid";
  command_to_info_[LC_RPATH] = "LC_RPATH * runpath additions";
  command_to_info_[LC_CODE_SIGNATURE] =
      "LC_CODE_SIGNATURE * local of code signature";
  command_to_info_[LC_SEGMENT_SPLIT_INFO] =
      "LC_SEGMENT_SPLIT_INFO * local of info to split segments";
  command_to_info_[LC_REEXPORT_DYLIB] =
      "LC_REEXPORT_DYLIB * load and re-export dylib";
  command_to_info_[LC_LAZY_LOAD_DYLIB] =
      "LC_LAZY_LOAD_DYLIB * delay load of dylib until first use";
  command_to_info_[LC_ENCRYPTION_INFO] =
      "LC_ENCRYPTION_INFO * encrypted segment information";
  command_to_info_[LC_DYLD_INFO] =
      "LC_DYLD_INFO * compressed dyld information";
  command_to_info_[LC_DYLD_INFO_ONLY] = ""
      "LC_DYLD_INFO_ONLY * compressed dyld information only";
  command_to_info_[LC_LOAD_UPWARD_DYLIB] =
      "LC_LOAD_UPWARD_DYLIB * load upward dylib";
  command_to_info_[LC_VERSION_MIN_MACOSX] =
      "LC_VERSION_MIN_MACOSX * build for MacOSX min OS version";
  command_to_info_[LC_VERSION_MIN_IPHONEOS] =
      "LC_VERSION_MIN_IPHONEOS * build for iPhoneOS min OS version";
  command_to_info_[LC_FUNCTION_STARTS] =
      "LC_FUNCTION_STARTS * compressed table of function start addresses";
  command_to_info_[LC_DYLD_ENVIRONMENT] =
      "LC_DYLD_ENVIRONMENT * string for dyld to treat like environment "
          "variable";
  command_to_info_[LC_MAIN] = "LC_MAIN * replacement for LC_UNIXTHREAD";
  command_to_info_[LC_DATA_IN_CODE] =
      "LC_DATA_IN_CODE * table of non-instructions in __text";
  command_to_info_[LC_SOURCE_VERSION] =
      "LC_SOURCE_VERSION * source version used to build binary";
  command_to_info_[LC_DYLIB_CODE_SIGN_DRS] =
      "LC_DYLIB_CODE_SIGN_DRS * Code signing DRs copied from linked dylibs";
  command_to_info_[LC_ENCRYPTION_INFO_64] =
      "LC_ENCRYPTION_INFO_64 * 64-bit encrypted segment information";
  command_to_info_[LC_LINKER_OPTION] =
      "LC_LINKER_OPTION * linker options in MH_OBJECT files";
  command_to_info_[LC_LINKER_OPTIMIZATION_HINT] =
      "LC_LINKER_OPTIMIZATION_HINT * optimization hints in MH_OBJECT files";
#ifndef __OPEN_SOURCE__
  command_to_info_[LC_VERSION_MIN_TVOS] =
      "LC_VERSION_MIN_TVOS * build for AppleTV min OS version";
#endif /* __OPEN_SOURCE__ */
  command_to_info_[LC_VERSION_MIN_WATCHOS] =
      "LC_VERSION_MIN_WATCHOS * build for Watch min OS version";
}

}  // namespace post_processor
