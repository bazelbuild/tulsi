// Copyright 2021 Wendy Liga. All rights reserved.
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

import Cocoa

class OpenSourceLicenseWindowController: NSWindowController {
  @IBOutlet var textView: NSScrollView!
  
  let tulsiTitle = NSAttributedString(
    string: "Tulsi",
    attributes: [.font: NSFont.titleBarFont(ofSize: 28)]
  )
  
  let tulsiLink: NSMutableAttributedString = {
    let link = "https://github.com/bazelbuild/tulsi"
    let range = NSRange(location: 0, length: link.count)
    
    let mutableAttributedString = NSMutableAttributedString(
      string: link,
      attributes: [.font : NSFont.systemFont(ofSize: 12)]
    )
    mutableAttributedString.addAttribute(.link, value: link, range: range)
    return mutableAttributedString
  }()
  
  let tulsiLicense = NSAttributedString(
    string: """
    Copyright 2016 The Tulsi Authors. All rights reserved.
    
    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at
    
          http://www.apache.org/licenses/LICENSE-2.0
    
    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
    """,
    attributes: [.font: NSFont.systemFont(ofSize: 14)]
  )
  
  let bazelTitle = NSAttributedString(
    string: "Bazel",
    attributes: [.font: NSFont.titleBarFont(ofSize: 28)]
  )
  
  let bazelLink: NSMutableAttributedString = {
    let link = "https://github.com/bazelbuild/bazel"
    let range = NSRange(location: 0, length: link.count)
    
    let mutableAttributedString = NSMutableAttributedString(
      string: link,
      attributes: [.font : NSFont.systemFont(ofSize: 12)]
    )
    mutableAttributedString.addAttribute(.link, value: link, range: range)
    return mutableAttributedString
  }()
  
  let bazelLicense = NSAttributedString(
    string: """
    Copyright 2017 The Bazel Authors. All rights reserved.
    
    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at
    
          http://www.apache.org/licenses/LICENSE-2.0
    
    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
    """,
    attributes: [.font: NSFont.systemFont(ofSize: 14)]
  )
  
  let sparkleTitle = NSAttributedString(
    string: "Sparkle",
    attributes: [.font: NSFont.titleBarFont(ofSize: 28)]
  )
  
  let sparkleLink: NSMutableAttributedString = {
    let link = "https://github.com/sparkle-project/Sparkle"
    let range = NSRange(location: 0, length: link.count)
    
    let mutableAttributedString = NSMutableAttributedString(
      string: link,
      attributes: [.font : NSFont.systemFont(ofSize: 12)]
    )
    mutableAttributedString.addAttribute(.link, value: link, range: range)
    return mutableAttributedString
  }()
  
  let sparkleLicense = NSAttributedString(
    string: """
    Copyright (c) 2006-2013 Andy Matuschak.
    Copyright (c) 2009-2013 Elgato Systems GmbH.
    Copyright (c) 2011-2014 Kornel Lesiński.
    Copyright (c) 2015-2017 Mayur Pawashe.
    Copyright (c) 2014 C.W. Betts.
    Copyright (c) 2014 Petroules Corporation.
    Copyright (c) 2014 Big Nerd Ranch.
    All rights reserved.

    Permission is hereby granted, free of charge, to any person obtaining a copy of
    this software and associated documentation files (the "Software"), to deal in
    the Software without restriction, including without limitation the rights to
    use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
    the Software, and to permit persons to whom the Software is furnished to do so,
    subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
    FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
    COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
    IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
    CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

    =================
    EXTERNAL LICENSES
    =================

    bspatch.c and bsdiff.c, from bsdiff 4.3 <http://www.daemonology.net/bsdiff/>:
        Copyright (c) 2003-2005 Colin Percival.

    sais.c and sais.c, from sais-lite (2010/08/07) <https://sites.google.com/site/yuta256/sais>:
        Copyright (c) 2008-2010 Yuta Mori.

    SUSignatureVerifier.m:
        Copyright (c) 2011 Mark Hamlin.

    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted providing that the following conditions
    are met:
    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.

    THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
    IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
    WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
    ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
    DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
    DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
    OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
    HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
    STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
    IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
    """,
    attributes: [.font: NSFont.systemFont(ofSize: 14)]
  )
  
  override var windowNibName: NSNib.Name? {
    "OpenSourceLicenseWindowController"
  }
  
  override func windowDidLoad() {
    super.windowDidLoad()
    
    let text = NSMutableAttributedString()
    text.append(tulsiTitle)
    text.append(below())
    text.append(tulsiLink)
    text.append(newLine())
    text.append(tulsiLicense)
    text.append(newSection())
    text.append(bazelTitle)
    text.append(below())
    text.append(bazelLink)
    text.append(newLine())
    text.append(bazelLicense)
    text.append(newSection())
    text.append(sparkleTitle)
    text.append(below())
    text.append(sparkleLink)
    text.append(newLine())
    text.append(sparkleLicense)
    
    textView.documentView?.insertText(text)
    textView.documentView?.scroll(.zero) // stay on top
    (textView.documentView as! NSTextView).textContainerInset = CGSize(width: 16, height: 16)
    (textView.documentView as! NSTextView).isEditable = false
  }
  
  func below() -> NSAttributedString {
    NSAttributedString(string: "\n")
  }
  
  func newLine() -> NSAttributedString {
    NSAttributedString(string: "\n\n")
  }
  
  func newSection() -> NSAttributedString {
    NSAttributedString(string: "\n\n\n\n")
  }
}
