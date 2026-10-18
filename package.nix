# mcpp — the prebuilt release binaries, the same artifacts install.sh and the
# AUR's mcpp-bin download. See README.md.
#
# The version and the hashes are not written here: they are read from
# release.json, which is the `mcpp-release.json` asset of a release, copied
# verbatim by scripts/update.sh.
{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
}:

let
  release = lib.importJSON ./release.json;

  # A manifest schema this file was not written for fails here, by name,
  # rather than as a missing attribute further down.
  checkedRelease =
    assert lib.assertMsg (
      release.schema == 1
    ) "release.json: schema ${toString release.schema} is not supported (expected 1)";
    release;

  # Nix system -> the (platform, arch) pair the manifest names an asset by.
  assetKeys = {
    x86_64-linux = {
      platform = "linux";
      arch = "x86_64";
    };
    aarch64-linux = {
      platform = "linux";
      arch = "aarch64";
    };
    aarch64-darwin = {
      platform = "macos";
      arch = "arm64";
    };
  };

  system = stdenvNoCC.hostPlatform.system;
  key = assetKeys.${system} or (throw "mcpp: no release asset for ${system}");
  asset = lib.findFirst (
    a: a.platform == key.platform && a.arch == key.arch
  ) (throw "mcpp: release.json has no ${key.platform}/${key.arch} asset") checkedRelease.assets;
in
stdenvNoCC.mkDerivation {
  pname = "mcpp";
  inherit (checkedRelease) version;

  src = fetchurl {
    url = "https://github.com/mcpp-community/mcpp/releases/download/${checkedRelease.tag}/${asset.name}";
    inherit (asset) sha256;
  };

  nativeBuildInputs = [ makeWrapper ];

  # Static upstream binaries: nothing to patch, and stripping the bundled
  # xlings would change a third-party artifact.
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  dontPatchELF = true;

  # The tree keeps the release layout under libexec: mcpp finds the xlings it
  # was released with at <prefix>/registry/bin/xlings beside <prefix>/bin/mcpp.
  #
  # The wrapper is not optional. mcpp takes <prefix> as its home when it runs
  # from <prefix>/bin/mcpp, and a store path is read-only, so the first write
  # would fail. MCPP_HOME and MCPP_VENDORED_XLINGS are pinned exactly as the
  # AUR's mcpp-bin pins them (tools/aur/mcpp-bin/mcpp.sh), and a value the user
  # already exported wins.
  installPhase = ''
    runHook preInstall

    install -Dm755 bin/mcpp            $out/libexec/mcpp/bin/mcpp
    install -Dm755 registry/bin/xlings $out/libexec/mcpp/registry/bin/xlings
    install -Dm644 LICENSE             $out/share/licenses/mcpp/LICENSE
    install -Dm644 README.md           $out/share/doc/mcpp/README.md

    makeWrapper $out/libexec/mcpp/bin/mcpp $out/bin/mcpp \
      --run 'export MCPP_HOME="''${MCPP_HOME:-$HOME/.mcpp}"' \
      --run 'export MCPP_VENDORED_XLINGS="''${MCPP_VENDORED_XLINGS:-'"$out"'/libexec/mcpp/registry/bin/xlings}"'

    runHook postInstall
  '';

  # `--version` reads no home and writes nothing; it proves the binary runs and
  # that the asset is the release the manifest names.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    out_version=$(HOME="$TMPDIR" $out/bin/mcpp --version)
    echo "$out_version"
    [ "$out_version" = "mcpp ${checkedRelease.version}" ]
    runHook postInstallCheck
  '';

  passthru = {
    inherit (checkedRelease) commit;
  };

  meta = {
    description = "Modern C++ build & package management tool (prebuilt binary)";
    homepage = "https://github.com/mcpp-community/mcpp";
    changelog = "https://github.com/mcpp-community/mcpp/releases/tag/${checkedRelease.tag}";
    license = lib.licenses.asl20;
    mainProgram = "mcpp";
    platforms = builtins.attrNames assetKeys;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
