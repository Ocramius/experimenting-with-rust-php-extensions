{
  description = "Rust PHP extension playground";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    naersk = {
      url = "github:nmattia/naersk";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, fenix, flake-utils, nixpkgs, naersk, ... }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = (import nixpkgs) {
          inherit system;

          # to allow for rust-rover to be installed
          config.allowUnfree = true;
        };

        toolchain = with fenix.packages.${system};
          combine [
            minimal.rustc
            minimal.cargo
            stable.rust-src
            stable.rustfmt
            stable.clippy
            stable.rust-analyzer
            #targets.x86_64-unknown-linux-musl.latest.rust-std
          ];

        naersk' = naersk.lib.${system}.override {
          cargo = toolchain;
          rustc = toolchain;
        };

        packagesNeededForPhpizeAndStdlib = [
          # needed to have `phpize` and `php-config`
          pkgs.php.unwrapped.dev

          # needed by `phpize` and `php-config` and similar
          pkgs.llvmPackages.clang
          # needed for `stdlib.h`:
          # https://discourse.nixos.org/t/stdlib-h-no-such-file-or-directory/20326/2
          # https://github.com/NixOS/nixpkgs/issues/214524
          pkgs.llvmPackages.libcxx
        ];

        PHP = "${pkgs.php}/bin/php";
        PHP_CONFIG = "${pkgs.php.unwrapped.dev}/bin/php-config";
        LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";

        phpPath = nixpkgs.makeBinPath [pkgs.php pkgs.php.unwrapped];

        built = naersk'.buildPackage {
          src = ./.;
          doCheck = true;
          copyLibs = true;
          nativeBuildInputs = packagesNeededForPhpizeAndStdlib;

          inherit PHP;
          inherit PHP_CONFIG;
          inherit LIBCLANG_PATH;
        };

        builtExtension = pkgs.stdenv.mkDerivation {
          name = "libexperimenting_with_rust_php_extensions";
          extensionName = "libexperimenting_with_rust_php_extensions";

          src = built;

          # see https://github.com/NixOS/nixpkgs/blob/5735d1c8f48dad9a67aa06e8bbe7d779424472f0/pkgs/top-level/php-packages.nix#L191
          installPhase = ''
            mkdir -p $out/lib/php/extensions
            cp $src/lib/libexperimenting_with_rust_php_extensions.so $out/lib/php/extensions/
          '';
        };
      in {
        packages = {
          default = builtExtension;
        };

        devShells = {
          default = pkgs.mkShell {
            name = "rust-php-extension-playground dev shell";

            nativeBuildInputs = [
              # needed for Linux compilation overall
              pkgs.openssl
              pkgs.pkg-config

              pkgs.jetbrains.rust-rover
              toolchain
            ] ++ packagesNeededForPhpizeAndStdlib;

            RUST_SRC_PATH="${toolchain}/lib/rustlib/src/rust/library";

            inherit PHP;
            inherit PHP_CONFIG;
            inherit LIBCLANG_PATH;
          };
        };

        checks = {
          runs-extension = pkgs.stdenv.mkDerivation {
            name = "can run php with the extension loaded";

            src = ./.;

            doCheck = true;

            nativeBuildInputs = [
              pkgs.php
            ];

            checkPhase = ''
              echo "extension=${built}/lib/libexperimenting_with_rust_php_extensions.so" > ./php.ini

              OUTPUT=$(${pkgs.php}/bin/php -c ./php.ini -r "echo my_custom_extension('testing');")

              if [[ "$OUTPUT" = 'From my custom extension: testing!' ]]; then
                echo "OK" >> $out;
              else
                echo "KO" >> $out;
                exit 1;
             fi
            '';
          };

          runs-extension-preinstalled-with-php =
          let
            php-with-extension = (pkgs.php.buildEnv {
              extensions = ({ enabled, all }: enabled ++ [builtExtension]);
            });
          in pkgs.stdenv.mkDerivation {
            name = "can run php with the extension pre-installed";

            src = ./.;

            doCheck = true;

            nativeBuildInputs = [
              php-with-extension
            ];

            checkPhase = ''
              echo "HI!"
              ${php-with-extension}/bin/php -m
              OUTPUT=$(${php-with-extension}/bin/php -r "echo my_custom_extension('preinstalled');")

              if [[ "$OUTPUT" = 'From my custom extension: preinstalled!' ]]; then
                echo "OK" >> $out;
              else
                echo "KO" >> $out;
                exit 1;
             fi
            '';
          };
        };
      }
    );
}
