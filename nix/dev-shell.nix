{ pkgs, quickshellWrapped }:

# Everything dots/.config/quickshell/imi/tests/run_tests.sh reaches for:
# qmltestrunner (shipped by qt6.qtdeclarative), python3 with the two
# third-party modules the pixel-scoring tests import (PIL, numpy), weston
# for the headless runtime harnesses, dbus-run-session for the harnesses
# that lint_runtime_bus_isolation.py holds to their own bus, and the
# wrapped quickshell for the qs -p probes. matugen is here because the
# colour-generation tests drive it.
let
  inherit (pkgs) lib;
  qtLibs = with pkgs.qt6; [
    qtbase
    qtdeclarative
    qt5compat
    qtsvg
    qtimageformats
    qtmultimedia
    qtwayland
  ];
in
pkgs.mkShell {
  packages = qtLibs ++ [
    quickshellWrapped
    (pkgs.python3.withPackages (ps: with ps; [ pillow numpy ]))
    pkgs.weston
    pkgs.dbus
    pkgs.matugen
  ];

  # An interactive mkShell does not wrap Qt tools, so qmltestrunner needs to
  # be told where the platform plugins and QML modules are. run_tests.sh
  # already defaults QT_QPA_PLATFORM=offscreen itself.
  shellHook = ''
    export QT_PLUGIN_PATH="${lib.makeSearchPath pkgs.qt6.qtbase.qtPluginPrefix qtLibs}''${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
    export QML2_IMPORT_PATH="${lib.makeSearchPath pkgs.qt6.qtbase.qtQmlPrefix qtLibs}''${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"
    echo "Immaterial Impulse dev shell."
    echo "Run the suite with: dots/.config/quickshell/imi/tests/run_tests.sh"
  '';
}
