# pkgsrc-impurifier

Generate native pkgsrc binary packages containing Nix application intent and,
for offline packages, the application closure. Packages install into the host
root and publish commands through `/opt/nix/profile`.

```nix
let
  impurifier = inputs.pkgsrc-impurifier.lib.pkgsrc-impurifier { inherit pkgs; };
in impurifier.makePackage { pkg = pkgs.hello; }
```

`makePackage` returns `net` and `offline`; `makeNetPackage` and
`makeOfflinePackage` select one. Native package names remain stable across
transports: version revision `nb1` selects net, `nb2` selects offline. Use native
`pkg_add -U` to replace an installed package, including transport changes.
`pkgsrc-impurifier install ARCHIVE...` runs that native operation and reports
activation failures; `reconcile` retries activation, and `remove PACKAGE...`
runs `pkg_delete` before reconciling.

Use the impurifier command when activation status matters. Native post-install
hooks print activation failures but return success so pkgsrc retains the installed
package for retry. The adapter returns a nonzero status for that failed activation.
Failed closure imports preserve the previous profile; lifecycle hooks run with the
new profile already published and remain pending until a successful retry.

Install `makeRuntimePackage` first. `nixDependency`, `pythonDependency`,
`pythonExecutable`, and `nativeBinPath` express the host's real providers and
paths. Defaults expect a `nix` provider and pkgsrc's `python314`, with tools under
`/usr/pkg`. The Nix provider itself remains deferred installer work; this project
does not imply that upstream pkgsrc supplies one. `hostDependencies` accepts
native pkgsrc package patterns. `osVersion` records the intended Linux kernel
version in required native build metadata, defaulting to the pinned Nixpkgs
kernel version. Native platform checks remain enabled.

Configuration files use pkgsrc's reference-counted configuration helper and
example files. Administrator edits are preserved across upgrades and removal.
Accounts, directories, lifecycle hooks and explicit host-library capture use the
shared impurifier engine. Systemd service policy is covered by the native VM;
OpenRC and runit integration remain pending. After an unrelated native driver update, run
`pkgsrc-impurifier reconcile` to refresh captured host libraries.

The package root is `/`; alternate `PKG_DESTDIR` and prefix relocation are
rejected by installation hooks. Package dependencies and native reverse
relations remain pkgsrc's responsibility. Original code is MIT licensed; native
source notices are described in [THIRD_PARTY.md](THIRD_PARTY.md).
