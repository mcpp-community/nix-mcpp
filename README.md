# nix-mcpp

Nix flake for [**mcpp**](https://github.com/mcpp-community/mcpp) — a modern,
module-first C++23 build & package management tool.

```sh
nix run github:mcpp-community/nix-mcpp -- --version      # try it
nix profile install github:mcpp-community/nix-mcpp       # install it
```

The flake packages the **prebuilt release binaries** — the same tarballs
upstream's `install.sh`, the AUR's `mcpp-bin` and
[homebrew-mcpp](https://github.com/mcpp-community/homebrew-mcpp) install. It
does not build mcpp from source: mcpp is self-hosted and downloads its own
toolchain, which the Nix build sandbox does not allow.

## Outputs

| output | systems | what it is |
|---|---|---|
| `packages.<system>.mcpp` (= `default`) | x86_64-linux, aarch64-linux, aarch64-darwin | the release, with a wrapper |
| `overlays.default` | — | adds `pkgs.mcpp-bin` |
| `devShells.<system>.default` | as above | `mcpp`, git, jq, python3, gh, shellcheck — to work on an mcpp checkout |
| `checks.<system>.mcpp` | as above | the package; its install check runs `mcpp --version` |

As a flake input:

```nix
{
  inputs.mcpp.url = "github:mcpp-community/nix-mcpp";

  # NixOS / home-manager:
  #   nixpkgs.overlays = [ inputs.mcpp.overlays.default ];
  #   environment.systemPackages = [ pkgs.mcpp-bin ];
  # or directly:
  #   inputs.mcpp.packages.${system}.default
}
```

## Why `mcpp-bin` in the overlay

`pkgs.mcpp` in nixpkgs is [Matsui's C preprocessor](https://search.nixos.org/packages?query=mcpp),
an unrelated project. The overlay does not replace it — whatever depends on the
preprocessor keeps working — so the attribute is `mcpp-bin`, the same reason
upstream ships `mcpp-bin` on the AUR and PyPI. The command is always `mcpp`.

## What gets installed, and where

```
$out/bin/mcpp                            wrapper
$out/libexec/mcpp/bin/mcpp               the static release binary
$out/libexec/mcpp/registry/bin/xlings    the xlings released with it
```

The wrapper sets

- `MCPP_HOME` to `$HOME/.mcpp` — mcpp takes `<prefix>` as its home when it runs
  from `<prefix>/bin/mcpp`, and a store path is read-only;
- `MCPP_VENDORED_XLINGS` to the xlings released with it.

A value already exported wins, as with the AUR wrapper. Per-user data —
toolchains, the package index, the BMI cache — lives in `~/.mcpp/`, shared with
any other mcpp install on the machine. Removing the package leaves it; delete
`~/.mcpp` to remove it too.

## NixOS

mcpp itself is a static binary and runs anywhere. The toolchains it installs
into `~/.mcpp` on first build (gcc, llvm, binutils, ninja) are ordinary Linux
binaries; if one fails to start on NixOS, enable

```nix
programs.nix-ld.enable = true;
```

The flake does not wrap mcpp in an FHS environment.

## Updating

`.github/workflows/bump.yml` keeps `release.json` at the newest release:

- `repository_dispatch` (`mcpp-release`) — when upstream's release pipeline pings;
- `schedule` — daily catch-up, so the flake follows releases with no token upstream;
- `workflow_dispatch` — manual pin / re-run.

Each run calls `scripts/update.sh`, which copies the release's
`mcpp-release.json` verbatim into `release.json`. That asset is uploaded after
every platform's tarball, so a release still in progress is skipped until the
next run. A manifest with another `schema`, a missing asset, or a version older
than the current one is refused. Before the commit, the x86_64-linux package is
built and run, and the aarch64-linux / aarch64-darwin assets are prefetched
against the hashes the flake evaluates to.

By hand:

```sh
./scripts/update.sh                # latest
./scripts/update.sh 2026.10.17.1   # a given version
nix flake check -L
```

## License

Apache-2.0, as upstream.
