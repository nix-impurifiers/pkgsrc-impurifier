# SPDX-License-Identifier: MIT
{
  pkgs,
  coreSrc,
  sourceInfo ? { },
}:
let
  inherit (pkgs) lib;
  core = import (coreSrc + "/nix") {
    inherit pkgs;
    namespace = "pkgsrc-impurifier";
    sourceInfo.lastModified = lib.max (
      if builtins.isAttrs coreSrc then coreSrc.lastModified or 0 else 0
    ) (if builtins.isAttrs sourceInfo then sourceInfo.lastModified or 0 else 0);
  };
  tools = import ./tools.nix { inherit pkgs; };
  buildPackage =
    {
      name,
      version,
      payload,
      dependencies ? [ ],
      conflicts ? [ ],
      installScript ? "",
      removeScript ? "",
      description ? "Nix projected application",
      osVersion ? pkgs.linux.version,
      license ? "mit",
    }:
    assert lib.assertMsg (lib.all (v: builtins.match "[a-z0-9][a-z0-9+._-]*" v != null) [
      name
      version
    ]) "invalid pkgsrc package identity";
    pkgs.runCommand "${name}-${version}-pkgsrc"
      {
        nativeBuildInputs = [
          tools.package
          pkgs.python3
        ];
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
        passthru = { inherit name version; };
      }
      ''
        mkdir -p "$out" root
        cp -r ${payload}/. root/
        chmod -R u+w root
        python3 - "$PWD/root" <<'PY'
        from pathlib import Path
        import sys
        root = Path(sys.argv[1])
        with open('PLIST', 'w') as stream:
            for path in sorted(root.rglob('*')):
                relative = str(path.relative_to(root))
                if '\n' in relative or relative.startswith('@'):
                    raise ValueError('invalid packing-list filename')
                if path.is_symlink() or path.is_file():
                    stream.write(relative + '\n')
                elif path.is_dir():
                    stream.write('@pkgdir ' + relative + '\n')
                else:
                    raise ValueError('unsupported payload entry')
        PY
        printf '%s\n' 'OPSYS=Linux' 'MACHINE_ARCH=x86_64' ${
          lib.escapeShellArg ("OS_VERSION=" + osVersion)
        } ${lib.escapeShellArg ("LICENSE=" + license)} 'PKGTOOLS_VERSION=20260227' > BUILD_INFO
        pkg_create -p "$PWD/root" -I / -u root -g root \
          -B BUILD_INFO -f PLIST -F gzip \
          -c ${lib.escapeShellArg ("-" + description)} -d ${lib.escapeShellArg ("-" + description)} \
          ${
            lib.optionalString (dependencies != [ ]) (
              "-P " + lib.escapeShellArg (lib.concatStringsSep " " dependencies)
            )
          } \
          ${
            lib.optionalString (conflicts != [ ]) (
              "-C " + lib.escapeShellArg (lib.concatStringsSep " " conflicts)
            )
          } \
          ${
            lib.optionalString (installScript != "") ("-i " + toString (pkgs.writeText "INSTALL" installScript))
          } \
          ${
            lib.optionalString (removeScript != "") ("-k " + toString (pkgs.writeText "DEINSTALL" removeScript))
          } \
          "$out/${name}-${version}.tgz"
      '';
  configTemplate = builtins.readFile (tools.source + "/mk/pkginstall/files");
  substitutions = {
    SH = "/bin/sh";
    PREFIX = "/";
    PKG_CONFIG = "yes";
    PKG_CONFIG_PERMS = "yes";
    PKG_RCD_SCRIPTS = "no";
    AWK = "awk";
    CAT = "cat";
    CHGRP = "chgrp";
    CHMOD = "chmod";
    CHOWN = "chown";
    CMP = "cmp";
    CP = "cp";
    ECHO = "echo";
    GREP = "grep";
    LS = "ls";
    MKDIR = "mkdir";
    MV = "mv";
    PWD_CMD = "pwd";
    RM = "rm";
    RMDIR = "rmdir";
    SED = "sed";
    SORT = "sort";
    TEST = "test";
    TRUE = "true";
  };
  nativeConfigScript = lib.replaceStrings (map (key: "@${key}@") (
    builtins.attrNames substitutions
  )) (builtins.attrValues substitutions) configTemplate;
  hooks =
    configFiles:
    let
      records = lib.concatMapStringsSep "\n" (
        path:
        let
          value = configFiles.${path};
          mode = if builtins.isAttrs value && !(lib.isDerivation value) then value.mode or "0644" else "0644";
        in
        "# FILE: ${path} c /usr/share/pkgsrc-impurifier/examples${path} ${mode} root root"
      ) (builtins.attrNames configFiles);
    in
    ''
      #!/bin/sh
      # Original integration code: MIT. Native config helper: pkgsrc.
      CAT=cat
      SED=sed
      CHMOD=chmod
      SELF=$0
      PKGNAME=$1
      STAGE=$2
      shift 2
      case "$STAGE" in
        PRE-INSTALL|DEINSTALL)
          [ "''${ROOT:-/}" = / ] && [ "''${DESTDIR:-/}" = / ] && [ "''${PKG_DESTDIR:-/}" = / ] && [ "''${PKG_PREFIX:-/}" = / ] || exit 1
          ;;
      esac
      ${nativeConfigScript}
      ${records}
      case "$STAGE" in
        PRE-INSTALL)
          sh "$SELF" "$PKGNAME" UNPACK +FILES || exit 1
          ;;
        POST-INSTALL)
          ./+FILES ADD "$PKG_METADATA_DIR" && ./+FILES PERMS "$PKG_METADATA_DIR" || exit 1
          if [ -x /usr/sbin/pkgsrc-impurifier-activate ]; then
              /usr/sbin/pkgsrc-impurifier-activate || echo 'pkgsrc-impurifier: activation failed; use pkgsrc-impurifier reconcile to retry' >&2
            fi
          ;;
        DEINSTALL)
          [ ! -x ./+FILES ] || ./+FILES REMOVE "$PKG_METADATA_DIR" || exit 1
          ;;
        POST-DEINSTALL)
          [ ! -x /usr/sbin/pkgsrc-impurifier-activate ] || /usr/sbin/pkgsrc-impurifier-activate remove
          ;;
      esac
    '';
  makeRuntimePackage =
    {
      nixDependency ? "nix>=0",
      pythonDependency ? "python314>=0",
      pythonExecutable ? "/usr/pkg/bin/python3.14",
      nativeBinPath ? "/usr/pkg/sbin:/usr/pkg/bin",
      version ? core.runtimeVersion,
      osVersion ? pkgs.linux.version,
    }:
    assert lib.assertMsg (
      builtins.match "/[A-Za-z0-9_./+-]+" pythonExecutable != null
      && builtins.match "[A-Za-z0-9_./:+-]+" nativeBinPath != null
    ) "native runtime tool paths must be absolute shell-safe paths";
    buildPackage {
      name = "pkgsrc-impurifier";
      inherit version osVersion;
      dependencies = [
        nixDependency
        pythonDependency
      ];
      installScript = hooks { };
      removeScript = hooks { };
      payload = pkgs.runCommand "pkgsrc-runtime" { } ''
        cp -r ${core.makeRuntimeTree { }} $out
        chmod -R u+w $out
        install -Dm755 ${../src/activate.py} $out/usr/sbin/pkgsrc-impurifier-activate
        install -Dm755 ${../src/adapter.py} $out/usr/sbin/pkgsrc-impurifier
        substituteInPlace $out/usr/sbin/nix-profile-engine --replace-fail /usr/bin/python3 ${lib.escapeShellArg pythonExecutable}
        for script in $out/usr/sbin/pkgsrc-impurifier $out/usr/sbin/pkgsrc-impurifier-activate; do
          substituteInPlace "$script" --replace-fail '#!/usr/bin/python3' ${
            lib.escapeShellArg ("#!" + pythonExecutable)
          }
          sed -i '/^import os$/a os.environ["PATH"] = ${builtins.toJSON nativeBinPath} + ":" + os.environ.get("PATH", "")' "$script"
        done
        substituteInPlace $out/usr/sbin/nix-profile-engine --replace-fail 'export PATH=' 'export PATH=${nativeBinPath}:'
        mkdir -p $out/usr/share/pkgsrc-impurifier
        echo '${version}'  > $out/usr/share/pkgsrc-impurifier/runtime-version
      '';
    };
  makePackageArtifact =
    args@{
      pkg,
      configFiles ? { },
      hostDependencies ? [ ],
      osVersion ? pkgs.linux.version,
      ...
    }:
    assert lib.assertMsg (
      (args.openrc or null) == null && (args.runit or null) == null
    ) "pkgsrc OpenRC/runit integration needs a separately verified host policy";
    let
      application = core.makePayload (
        (builtins.removeAttrs args [
          "hostDependencies"
          "osVersion"
        ])
        // {
          hostBackend = "systemd";
        }
      );
      callbacks = hooks configFiles;
    in
    buildPackage {
      name = application.name;
      version = "${application.version}nb${if application.offline then "2" else "1"}";
      inherit (application) description;
      inherit osVersion;
      dependencies = [ "pkgsrc-impurifier>=${core.runtimeVersion}" ] ++ hostDependencies;
      installScript = callbacks;
      removeScript = callbacks;
      payload = pkgs.runCommand "pkgsrc-application" { } ''
        cp -r ${application} $out
        chmod -R u+w $out
        mkdir -p $out/usr/share/pkgsrc-impurifier/requirements
        echo '${core.runtimeVersion}' > $out/usr/share/pkgsrc-impurifier/requirements/${application.name}
        ${lib.concatMapStringsSep "\n" (path: ''
          mkdir -p "$out/usr/share/pkgsrc-impurifier/examples$(dirname ${lib.escapeShellArg path})"
          mv "$out"${lib.escapeShellArg path} "$out/usr/share/pkgsrc-impurifier/examples"${lib.escapeShellArg path}
        '') (builtins.attrNames configFiles)}
      '';
    };
in
{
  inherit
    tools
    buildPackage
    makeRuntimePackage
    makePackageArtifact
    ;
  runtimePackage = makeRuntimePackage { };
  makeNetPackage = args: makePackageArtifact (args // { offline = false; });
  makeOfflinePackage = args: makePackageArtifact (args // { offline = true; });
  makePackage = args: {
    net = makePackageArtifact (args // { offline = false; });
    offline = makePackageArtifact (args // { offline = true; });
  };
  inherit (core) unit;
}
