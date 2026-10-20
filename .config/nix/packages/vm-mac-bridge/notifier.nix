{
  lib,
  stdenv,
  fetchurl,
  python3,
}:
stdenv.mkDerivation {
  pname = "vm-mac-bridge-notifier";
  version = "3.1.0";

  src = fetchurl {
    url = "https://github.com/julienxx/terminal-notifier/archive/refs/tags/3.1.0.tar.gz";
    hash = "sha256-faxEpWPwDBDUmqLaTN6dH+zbErNu1X/n/f94nDV4Qh4=";
  };

  nativeBuildInputs = [ python3 ];
  strictDeps = true;
  dontConfigure = true;

  # The upstream Makefile assumes Apple's CLT, PlistBuddy, and a universal
  # build. Use the Nix compiler/SDK and build for this host's architecture.
  buildPhase = ''
    runHook preBuild
    $CC -fobjc-arc -std=gnu11 -Os \
      -framework Cocoa -framework UserNotifications \
      -o terminal-notifier \
      'Terminal Notifier/main.m' 'Terminal Notifier/AppDelegate.m'
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    app="$out/Applications/vm-mac-bridge.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp terminal-notifier "$app/Contents/MacOS/terminal-notifier"
    cp Terminal.icns "$app/Contents/Resources/icon.icns"
    cp -R 'Terminal Notifier/en.lproj' "$app/Contents/Resources/"
    printf 'APPL????' > "$app/Contents/PkgInfo"
    python3 ${./prepare_plist.py} \
      'Terminal Notifier/Terminal Notifier-Info.plist' "$app/Contents/Info.plist"
    runHook postInstall
  '';

  meta = {
    description = "Dedicated approval notifications for the VM–Mac bridge";
    homepage = "https://github.com/julienxx/terminal-notifier";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
  };
}
