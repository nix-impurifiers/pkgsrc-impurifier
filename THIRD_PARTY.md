# Third-party software

Original integration code is MIT licensed.

Native pkgsrc tools, libnbcompat, libfetch, netpgpverify, and the reference-counted
configuration-file helper come from the official NetBSD/pkgsrc source revision
`7608a44568fd11823fea5fdcf17141cf84c21abc`. Original source notices are preserved.
The tool build compiles the upstream implementations and their bundled support
libraries; it does not replace them with a simulated package manager.

The native configuration helper is used with tool-path and policy placeholders
expanded for the host. Its original NetBSD source identification is retained in
generated install and deinstall scripts. The original helper source and native
support-library sources are included with the native tool output.
