# SPDX-License-Identifier: MIT
{ pkgs }:
let
  source = pkgs.fetchFromGitHub {
    owner = "NetBSD";
    repo = "pkgsrc";
    rev = "7608a44568fd11823fea5fdcf17141cf84c21abc";
    hash = "sha256-ywX9tybWHSPOIlsmSzPlk0x0HhREeNh1zl+Zj7QEVLY=";
  };
  package = pkgs.stdenv.mkDerivation {
    pname = "pkgsrc-package-tools";
    version = "20260227";
    dontUnpack = true;
    dontConfigure = true;
    nativeBuildInputs = [ pkgs.bmake ];
    buildInputs = [
      pkgs.libarchive
      pkgs.bzip2
      pkgs.zlib
      pkgs.openssl
    ];
    buildPhase = ''
      runHook preBuild
      cp -r ${source}/pkgtools/libnbcompat/files nbcompat
      cp -r ${source}/net/libfetch/files fetch
      cp -r ${source}/security/netpgpverify/files netpgp
      cp -r ${source}/pkgtools/pkg_install/files tools
      chmod -R u+w nbcompat fetch netpgp tools
      root=$PWD
      (cd nbcompat; bash ./configure --enable-bsd-getopt --enable-db; bmake -j$NIX_BUILD_CORES)
      export CPPFLAGS="-I$root/nbcompat -I$root/fetch -I$root $CPPFLAGS"
      export LDFLAGS="-L$root/nbcompat -L$root/fetch -L$root/netpgp $LDFLAGS"
      export LIBS="-lnbcompat"
      (cd fetch
        sh errlist.sh ftp_errlist FTP ftp.errors > ftperr.h
        sh errlist.sh http_errlist HTTP http.errors > httperr.h
        for file in fetch common ftp http file; do
          $CC $CPPFLAGS $NIX_CFLAGS_COMPILE -I. -DINET6 -DWITH_SSL -DFTP_COMBINE_CWDS -c "$file.c"
        done
        ar cr libfetch.a *.o
      )
      (cd netpgp; cp Makefile.lib.in Makefile.in; bash ./configure; bmake -j$NIX_BUILD_CORES)
      (cd tools
        bash ./configure --prefix=$out --sysconfdir=/etc/pkgsrc --with-pkgdbdir=/var/db/pkgsrc --with-ssl
        bmake OPSYS=Linux PKGSRC_MACHINE_ARCH=x86_64 -j$NIX_BUILD_CORES
      )
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      (cd tools; bmake prefix=$out install)
      mkdir -p $out/share/licenses/pkgsrc
      cp ${source}/pkgtools/pkg_install/files/lib/lib.h $out/share/licenses/pkgsrc/package-tools-notice.h
      mkdir -p $out/share/src/pkgsrc
      cp -r ${source}/pkgtools/pkg_install/files $out/share/src/pkgsrc/pkg_install
      cp -r ${source}/pkgtools/libnbcompat/files $out/share/src/pkgsrc/libnbcompat
      cp -r ${source}/net/libfetch/files $out/share/src/pkgsrc/libfetch
      cp -r ${source}/security/netpgpverify/files $out/share/src/pkgsrc/netpgpverify
      cp ${source}/mk/pkginstall/files $out/share/src/pkgsrc/config-files
      runHook postInstall
    '';
  };
in
{
  inherit source package;
}
