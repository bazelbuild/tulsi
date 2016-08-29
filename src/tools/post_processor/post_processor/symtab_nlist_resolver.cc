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

#include "symtab_nlist_resolver.h"

#include <mach-o/stab.h>


namespace post_processor {

SymtabNListResolver::SymtabNListResolver() {
  debug_type_to_info_[N_GSYM] = "N_GSYM - global symbol: name,,NO_SECT,type,0";
  debug_type_to_info_[N_FNAME] =
      "N_FNAME - procedure name (f77 kludge): name,,NO_SECT,0,0";
  debug_type_to_info_[N_FUN] =
      "N_FUN - procedure: name,,n_sect,linenumber,address";
  debug_type_to_info_[N_STSYM] =
      "N_STSYM - static symbol: name,,n_sect,type,address";
  debug_type_to_info_[N_LCSYM] =
      "N_LCSYM - .lcomm symbol: name,,n_sect,type,address";
  debug_type_to_info_[N_BNSYM] =
      "N_BNSYM - begin nsect sym: 0,,n_sect,0,address";
  debug_type_to_info_[N_AST] = "N_AST - AST file path: name,,NO_SECT,0,0";
  debug_type_to_info_[N_OPT] =
      "N_OPT - emitted with gcc2_compiled and in gcc source";
  debug_type_to_info_[N_RSYM] =
      "N_RSYM - register sym: name,,NO_SECT,type,register";
  debug_type_to_info_[N_SLINE] =
      "N_SLINE - src line: 0,,n_sect,linenumber,address";
  debug_type_to_info_[N_ENSYM] =
      "N_ENSYM - end nsect sym: 0,,n_sect,0,address";
  debug_type_to_info_[N_SSYM] =
      "N_SSYM - structure elt: name,,NO_SECT,type,struct_offset";
  debug_type_to_info_[N_SO] =
      "N_SO - source file name: name,,n_sect,0,address";
  debug_type_to_info_[N_OSO] = "N_OSO - object file name: name,,0,0,st_mtime";
  debug_type_to_info_[N_LSYM] =
      "N_LSYM - local sym: name,,NO_SECT,type,offset";
  debug_type_to_info_[N_BINCL] =
      "N_BINCL - include file beginning: name,,NO_SECT,0,sum";
  debug_type_to_info_[N_SOL] =
      "N_SOL - #included file name: name,,n_sect,0,address";
  debug_type_to_info_[N_PARAMS] =
      "N_PARAMS - compiler parameters: name,,NO_SECT,0,0";
  debug_type_to_info_[N_VERSION] =
      "N_VERSION - compiler version: name,,NO_SECT,0,0";
  debug_type_to_info_[N_OLEVEL] =
      "N_OLEVEL - compiler -O level: name,,NO_SECT,0,0";
  debug_type_to_info_[N_PSYM] =
      "N_PSYM - parameter: name,,NO_SECT,type,offset";
  debug_type_to_info_[N_EINCL] =
      "N_EINCL - include file end: name,,NO_SECT,0,0";
  debug_type_to_info_[N_ENTRY] =
      "N_ENTRY - alternate entry: name,,n_sect,linenumber,address";
  debug_type_to_info_[N_LBRAC] =
      "N_LBRAC - left bracket: 0,,NO_SECT,nesting level,address";
  debug_type_to_info_[N_EXCL] =
      "N_EXCL - deleted include file: name,,NO_SECT,0,sum";
  debug_type_to_info_[N_RBRAC] =
      "N_RBRAC - right bracket: 0,,NO_SECT,nesting level,address";
  debug_type_to_info_[N_BCOMM] = "N_BCOMM - begin common: name,,NO_SECT,0,0";
  debug_type_to_info_[N_ECOMM] = "N_ECOMM - end common: name,,n_sect,0,0";
  debug_type_to_info_[N_ECOML] =
      "N_ECOML - end common (local name): 0,,n_sect,0,address";
  debug_type_to_info_[N_LENG] =
      "N_LENG - second stab entry with length information";
  debug_type_to_info_[N_PC] =
      "N_PC - global pascal symbol: name,,NO_SECT,subtype,line";
}

}  // namespace post_processor
