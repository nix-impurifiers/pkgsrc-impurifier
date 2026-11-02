# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  coreSrc,
  tools,
}:
let
  package = impurifier.buildPackage {
    name = "native-marker";
    version = "1";
    payload = pkgs.runCommand "pkgsrc-native-marker" { } ''
      mkdir -p $out/usr/share/pkgsrc-vm
      echo native > $out/usr/share/pkgsrc-vm/marker
    '';
    installScript = ''
      #!/bin/sh
      [ "$2" != POST-INSTALL ] || echo installed > /var/pkgsrc-installed
    '';
    removeScript = ''
      #!/bin/sh
      [ "$2" != POST-DEINSTALL ] || echo removed > /var/pkgsrc-removed
    '';
  };
  tool =
    version:
    pkgs.runCommand "pkgsrc-tool-${version}"
      {
        pname = "pkgsrc-tool";
        inherit version;
        meta.license = pkgs.lib.licenses.mit;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${version}\n' > $out/bin/pkgsrc-tool
        chmod 755 $out/bin/pkgsrc-tool
      '';
  app =
    offline: version:
    impurifier.makePackageArtifact {
      pkg = tool version;
      inherit offline;
      configFiles."/etc/pkgsrc-app.conf" = pkgs.writeText "pkgsrc-app.conf" "version=${version}\n";
      users.pkgsrc-worker = { };
      directories."/var/lib/pkgsrc-worker" = {
        owner = "pkgsrc-worker:pkgsrc-worker";
        mode = "0750";
      };
      lifecycle = {
        onInstall = "echo initialized >> /var/lib/pkgsrc-worker/initialized";
        onUpgrade = "test ! -e /var/lib/pkgsrc-worker/fail; echo ${version} > /var/lib/pkgsrc-worker/migrated";
      };
    };
  provider =
    name: payload:
    impurifier.buildPackage {
      inherit name payload;
      version = "1";
    };
  nixProvider = provider "nix" (
    pkgs.runCommand "nix-provider-fixture" { } ''
      mkdir -p $out/usr/pkg/bin
      ln -s ${pkgs.nix}/bin/nix-store $out/usr/pkg/bin/nix-store
    ''
  );
  pythonProvider = provider "python314" (
    pkgs.runCommand "python-provider-fixture" { } ''
      mkdir -p $out/usr/pkg/bin
      ln -s ${pkgs.python3}/bin/python3 $out/usr/pkg/bin/python3.14
    ''
  );
  daemon =
    version:
    pkgs.runCommand "pkgsrc-service-${version}"
      {
        pname = "pkgsrc-service";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\nwhile true; do ${pkgs.busybox}/bin/sleep 60; done\n' > $out/bin/pkgsrc-service
        chmod 755 $out/bin/pkgsrc-service
      '';
  service =
    version:
    impurifier.makeOfflinePackage {
      pkg = daemon version;
      users.pkgsrc-service = { };
      directories."/var/lib/pkgsrc-service" = {
        owner = "pkgsrc-service:pkgsrc-service";
        mode = "0750";
      };
      lifecycle.onInstall = "test -d /var/lib/pkgsrc-service; echo initialized > /var/lib/pkgsrc-service/initialized";
      systemd.unit = pkgs.writeText "pkgsrc-service.service" ''
        [Service]
        Type=exec
        User=pkgsrc-service
        ExecStart=/opt/nix/profile/bin/pkgsrc-service
        [Install]
        WantedBy=multi-user.target
      '';
    };
  fixture = import (coreSrc + "/tests/hardware-fixture.nix") { inherit pkgs; };
  driver =
    version:
    impurifier.buildPackage {
      name = "host-driver";
      inherit version;
      payload = fixture.driver version;
    };
  hardware = impurifier.makeOfflinePackage {
    pkg = fixture.tool;
    inherit (fixture) hardware;
    hostDependencies = [ "host-driver>=1" ];
  };
  oldRuntime = impurifier.makeRuntimePackage { version = "0.1"; };
in
{
  native-package = package;
  native-vm = pkgs.testers.runNixOSTest {
    name = "pkgsrc-native-contract";
    requiredFeatures = {
      kvm = false;
      devnet = false;
    };
    nodes.machine = { lib, ... }: {
      virtualisation.qemu.package = lib.mkForce pkgs.qemu;
      virtualisation.qemu.forceAccel = false;
      environment.systemPackages = [
        tools.package
        pkgs.nix
        pkgs.coreutils
        pkgs.shadow
      ];
      system.extraDependencies = [ pkgs.python3 ];
      nix.settings.substituters = lib.mkForce [ ];
    };
    testScript = ''
      def succeed(command):
          return machine.succeed("export PATH=/usr/sbin:/usr/pkg/bin:$PATH; " + command)
      def fail(command):
          return machine.fail("export PATH=/usr/sbin:/usr/pkg/bin:$PATH; " + command)
      start_all()
      machine.wait_for_unit("multi-user.target")
      succeed("pkg_add ${package}/native-marker-1.tgz")
      succeed("grep native /usr/share/pkgsrc-vm/marker; grep installed /var/pkgsrc-installed; pkg_info -L native-marker | grep usr/share/pkgsrc-vm/marker")
      succeed("pkg_delete native-marker")
      succeed("test ! -e /usr/share/pkgsrc-vm/marker; grep removed /var/pkgsrc-removed")
      succeed("mkdir -p /usr/pkg/bin /usr/pkg/sbin; for executable in ${pkgs.coreutils}/bin/* ${pkgs.shadow}/bin/* ${tools.package}/bin/* ${pkgs.systemd}/bin/systemctl ${pkgs.systemd}/bin/systemd-sysusers ${pkgs.systemd}/bin/systemd-tmpfiles; do ln -sf \"$executable\" /usr/pkg/bin/; done")
      succeed("cp -rL /etc/systemd/system /tmp/systemd-system; chmod -R u+w /tmp/systemd-system; rm /etc/systemd/system; mv /tmp/systemd-system /etc/systemd/system; systemctl daemon-reload")
      succeed("pkg_add ${nixProvider}/nix-1.tgz ${pythonProvider}/python314-1.tgz")
      succeed("pkg_add ${impurifier.runtimePackage}/pkgsrc-impurifier-*.tgz")
      succeed("test ! -e ${builtins.unsafeDiscardStringContext (toString (tool "1"))}")
      fail("pkgsrc-impurifier install ${app false "1"}/pkgsrc-tool-*.tgz > /tmp/net.log 2>&1")
      succeed("pkgsrc-impurifier install ${app true "1"}/pkgsrc-tool-*.tgz > /tmp/offline.log 2>&1 || { cat /tmp/offline.log; exit 1; }")
      succeed("test $(/opt/nix/profile/bin/pkgsrc-tool) = 1; id pkgsrc-worker; test $(stat -c %a /var/lib/pkgsrc-worker) = 750; grep initialized /var/lib/pkgsrc-worker/initialized")
      succeed("echo customized > /etc/pkgsrc-app.conf; touch /var/lib/pkgsrc-worker/fail")
      fail("pkgsrc-impurifier install ${app false "2"}/pkgsrc-tool-*.tgz > /tmp/net-upgrade.log 2>&1")
      succeed("test $(/opt/nix/profile/bin/pkgsrc-tool) = 1")
      fail("pkgsrc-impurifier install ${app true "2"}/pkgsrc-tool-*.tgz > /tmp/upgrade.log 2>&1")
      succeed("test $(/opt/nix/profile/bin/pkgsrc-tool) = 2")
      succeed("rm /var/lib/pkgsrc-worker/fail; pkgsrc-impurifier reconcile; test $(/opt/nix/profile/bin/pkgsrc-tool) = 2; grep 2 /var/lib/pkgsrc-worker/migrated; test $(wc -l < /var/lib/pkgsrc-worker/initialized) = 1; grep customized /etc/pkgsrc-app.conf")
      succeed("pkgsrc-impurifier install ${service "1"}/pkgsrc-service-*.tgz > /tmp/service.log 2>&1 || { cat /tmp/service.log; exit 1; }")
      succeed("systemctl is-active pkgsrc-service; systemctl is-enabled pkgsrc-service; test -f /var/lib/pkgsrc-service/initialized")
      succeed("systemctl disable --now pkgsrc-service")
      succeed("pkgsrc-impurifier install ${service "2"}/pkgsrc-service-*.tgz > /tmp/service-upgrade.log 2>&1 || { cat /tmp/service-upgrade.log; exit 1; }")
      fail("systemctl is-active pkgsrc-service")
      fail("systemctl is-enabled pkgsrc-service")
      succeed("pkg_add -fUD ${oldRuntime}/pkgsrc-impurifier-*.tgz > /tmp/old-runtime.log 2>&1; grep '^0.1$' /usr/share/pkgsrc-impurifier/runtime-version")
      fail("pkgsrc-impurifier reconcile")
      succeed("test $(/opt/nix/profile/bin/pkgsrc-tool) = 2")
      succeed("pkg_add -U ${impurifier.runtimePackage}/pkgsrc-impurifier-*.tgz > /tmp/runtime-current.log 2>&1 || { cat /tmp/runtime-current.log; exit 1; }")
      succeed("pkgsrc-impurifier install ${driver "1"}/host-driver-*.tgz ${hardware}/hardware-tool-*.tgz > /tmp/hardware.log 2>&1 || { cat /tmp/hardware.log; exit 1; }; test $(/opt/nix/profile/bin/hardware-tool) = 1")
      succeed("pkg_add -U ${driver "2"}/host-driver-*.tgz; pkgsrc-impurifier reconcile; test $(/opt/nix/profile/bin/hardware-tool) = 2")
      succeed("nix-collect-garbage; test $(/opt/nix/profile/bin/pkgsrc-tool) = 2")
      fail("PKG_DESTDIR=/foreign pkgsrc-impurifier reconcile")
      succeed("pkgsrc-impurifier remove pkgsrc-service hardware-tool host-driver; test ! -e /opt/nix/profile/bin/pkgsrc-service")
      succeed("pkgsrc-impurifier remove pkgsrc-tool; test ! -e /opt/nix/profile/bin/pkgsrc-tool; grep customized /etc/pkgsrc-app.conf")

    '';
  };
}
