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

## Native payloads and bundled clients

`makeNativePackage { name; version; payload; dependencies?; ... }` packages a
producer-prepared filesystem tree with native pkg_create. It adds no engine
hooks or Nix dependency. The producer supplies a runnable target layout; no
relocation is performed. Linux x86_64 platform metadata remains the current SDK
contract. The target-root VM executes a static payload without `/nix`, upgrades
and removes it through native tools.

The pinned native SDK fixes pkg_add's `-P` upgrade subprocess to pass the original
database path to pkg_delete, which applies the destination root itself. Without
that one-line correction the root is applied twice. This fixture correction
does not alter generated package files; other native client versions need their
own compatibility check for destination-root upgrades.

`makeRuntimePackage` optionally accepts `bundledNixStore` and
`bundledNixNotices`. A static ELF client and upstream notices omit the default
Nix dependency; Python remains required. Compatible external clients take
precedence. Explicit `IMPURIFIER_NIX_STORE` disables fallback, and mutations are
never retried through another client. A separate bundled-client VM repeats
the original lifecycle suite with an incompatible external candidate.
