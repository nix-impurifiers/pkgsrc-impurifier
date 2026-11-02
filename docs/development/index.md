# Development

`nix/default.nix` builds canonical packages through native `pkg_create`, with
native package patterns, required platform metadata, and root-prefix ownership.
The high-level API uses stable package names and native `nb1`/`nb2` revisions for
transport choices. `nix/tools.nix` builds the complete upstream package tools,
including deletion, networking, and signature support.

Configuration installation uses the upstream pkgsrc `mk/pkginstall/files`
reference-counting helper. The original helper is expanded into install and
remove scripts, with example files packaged separately from live configuration.

`tests/default.nix` runs QEMU against real package creation, queries, installation,
replacement and deletion. It exercises import failures, lifecycle retries,
configuration edits, runtime gates, host preparation, service policy, explicit
host-library refresh, and GC. Native post-install callbacks deliberately report
but do not propagate engine failures to pkgsrc, which otherwise rolls back the
native package and prevents activation retries. The adapter reports those errors.

A Nix provider remains deferred installer work. VM provider packages describe the
Nix/Python tools preinstalled by the test fixture; they do not validate a new Nix
installation procedure. Distribution boot integration and OpenRC/runit service
coverage remain separate work.
