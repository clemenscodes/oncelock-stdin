{
  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-unstable";
    };
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
    };
    crane = {
      url = "github:ipetkov/crane";
    };
    fenix = {
      url = "github:nix-community/fenix";
      inputs = {
        nixpkgs = {
          follows = "nixpkgs";
        };
      };
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs = {
          follows = "nixpkgs";
        };
      };
    };
    advisory-db = {
      url = "github:rustsec/advisory-db";
      flake = false;
    };
    nix-filter = {
      url = "github:numtide/nix-filter";
    };
    lpi = {
      url = "github:cymenix/lpi";
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-parts,
    crane,
    fenix,
    rust-overlay,
    advisory-db,
    nix-filter,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      perSystem = {system, ...}: let
        inherit (pkgs) lib;

        rustToolchain = fenix.packages.${system}.fromToolchainFile {
          file = ./rust-toolchain.toml;
          sha256 = "sha256-lMLAupxng4Fd9F1oDw8gx+qA0RuF7ou7xhNU8wgs0PU=";
        };

        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (import rust-overlay)
            (final: prev: {
              lpi = inputs.lpi.packages.${system}.default;
            })
            (final: prev: {
              lib = prev.lib // {mergeDevShells = import ./nix/mergeDevShells.nix {pkgs = final;};};
            })
          ];
        };

        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

        src = nix-filter.lib {
          root = ./.;
          include = [
            ./Cargo.toml
            ./Cargo.lock
            ./taplo.toml
            ./rustfmt.toml
            ./rust-toolchain.toml
            ./deny.toml
            ./.config
            ./crates
          ];
        };

        inherit (craneLib.crateNameFromCargoToml {inherit src;}) version;

        args = {
          inherit src;
          strictDeps = true;
          buildInputs = [];
          nativeBuildInputs = [];
        };

        individualCrateArgs =
          args
          // {
            inherit cargoArtifacts version;
            doCheck = false;
          };

        fileSetForCrate = crateFiles:
          nix-filter.lib {
            root = ./.;
            include =
              [
                ./Cargo.toml
                ./Cargo.lock
                ./crates/workspace
              ]
              ++ crateFiles;
          };

        cargoArtifacts = craneLib.buildDepsOnly args;

        stub = craneLib.buildPackage (individualCrateArgs
          // {
            cargoExtraArgs = "-p stub";
            src = fileSetForCrate [
              ./crates/stub/src
              ./crates/stub/Cargo.toml
            ];
          });

        shells = {
          workspace = pkgs.mkShell {
            buildInputs = [
              pkgs.moon
              pkgs.lpi
            ];
            shellHook = ''
              moon sync projects
              export MOON=$(pwd)
            '';
          };
          rust = craneLib.devShell {
            checks = self.checks.${system};
            packages = [
              pkgs.rust-analyzer
              pkgs.cargo-watch
              pkgs.cargo-audit
              pkgs.cargo-deny
              pkgs.cargo-llvm-cov
              pkgs.cargo-tarpaulin
              pkgs.cargo-nextest
              pkgs.cargo-hakari
              pkgs.taplo
            ];
            RUST_SRC_PATH = "${craneLib.rustc}/lib/rustlib/src/rust/library";
            RUST_BACKTRACE = 1;
          };
        };
      in {
        formatter = pkgs.alejandra;

        checks = {
          inherit stub;

          doc = craneLib.cargoDoc (args // {inherit cargoArtifacts;});

          audit = craneLib.cargoAudit {inherit src advisory-db;};

          deny = craneLib.cargoDeny {inherit src;};

          coverage = craneLib.cargoLlvmCov (args // {inherit cargoArtifacts;});

          fmt = craneLib.cargoFmt {inherit src;};

          toml-fmt = craneLib.taploFmt {
            src = lib.sources.sourceFilesBySuffices src [".toml"];
            taploExtraArgs = "--config ./taplo.toml";
          };

          clippy = craneLib.cargoClippy (args
            // {
              inherit cargoArtifacts;
              cargoClippyExtraArgs = "--all-targets -- --deny warnings";
            });

          nextest = craneLib.cargoNextest (args
            // {
              inherit cargoArtifacts;
              partitions = 1;
              partitionType = "count";
            });

          hakari = craneLib.mkCargoDerivation {
            inherit src;
            pname = "workspace";
            cargoArtifacts = null;
            doInstallCargoArtifacts = false;
            nativeBuildInputs = [pkgs.cargo-hakari];
            buildPhaseCargoCommand = ''
              cargo hakari generate --diff
              cargo hakari manage-deps --dry-run
              cargo hakari verify
            '';
          };
        };

        packages = {
          inherit stub;
          default = self.packages.${system}.stub;
        };

        devShells = {
          default = lib.mergeDevShells (lib.attrsets.attrValues shells);
        };
      };
    };
}
