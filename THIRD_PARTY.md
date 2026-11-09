# Private multitouch ABI reference

The contact layout and private function signatures in `MultitouchBridge.c`
are adapted from [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport/blob/15c6bb0c6a2d2858559493a28ab23f7ac58648a3/Framework/OpenMultitouchSupportXCF/OpenMTInternal.h).
Device enumeration/service lookup and Magic Mouse family 112 were cross-checked
against the implementations cited in `research-magic-mouse.md`.
The app dynamically loads Apple's framework; no downloaded executable is bundled.

Native magnification event fields (type 29, subtype field 110/value 8,
magnification field 113, phase field 132) were cross-checked against
[Mac Mouse Fix's TouchSimulator](https://github.com/noah-nuebling/mac-mouse-fix/blob/master/Helper/Core/Touch/TouchSimulator.m#L79).
The Swift recognizer and output implementation are written for this app; no
Mac Mouse Fix source or executable is bundled. These field numbers describe
Apple's undocumented event format.

## OpenMultitouchSupport license

MIT License

Copyright (c) 2019 TakutoNakamura

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
