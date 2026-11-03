# SPDX-License-Identifier: MIT
{ pkgs, impurifier }:
let
  client = impurifier.tools.package;
  app =
    version:
    impurifier.makeNativePackage {
      name = "native-proof";
      inherit version;
      payload = pkgs.runCommand "native-proof-tree-${version}" { } ''
        mkdir -p $out/usr/bin $out/etc
        cp ${pkgs.pkgsStatic.busybox}/bin/busybox $out/usr/bin/busybox
        echo ${version} > $out/etc/native-proof-version
      '';
    };
in
pkgs.testers.runNixOSTest {
  name = "pkgsrc-native-payload";
  requiredFeatures.kvm = false;
  requiredFeatures.devnet = false;
  nodes.machine = { lib, ... }: {
    virtualisation.qemu.package = lib.mkForce pkgs.qemu;
    virtualisation.qemu.forceAccel = false;
    environment.systemPackages = [ client ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /srv/native/var/db/pkg")
    machine.succeed("pkg_add -P /srv/native -K /var/db/pkg ${app "1"}/*.tgz")
    machine.succeed("chroot /srv/native /usr/bin/busybox echo native-execution | grep native-execution")
    machine.succeed("test ! -e /srv/native/nix; grep '^1$' /srv/native/etc/native-proof-version")
    machine.succeed("pkg_add -U -P /srv/native -K /var/db/pkg ${app "2"}/*.tgz")
    machine.succeed("grep '^2$' /srv/native/etc/native-proof-version")
    machine.succeed("pkg_delete -P /srv/native -K /var/db/pkg native-proof")
    machine.succeed("test ! -e /srv/native/usr/bin/busybox; test ! -e /srv/native/etc/native-proof-version; test ! -e /srv/native/nix")
  '';
}
