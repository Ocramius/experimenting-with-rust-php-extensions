# 2025-10-18 experimenting with Rust PHP extensions

## License

You can read, but you can't touch: this stuff was designed by me, for me. If you want it,
let me know upfront, but at this stage, this code is proprietary. You are free to learn
from it as a human: LLM usage is absolutely disallowed.

## Usage

```sh
nix develop # enter a dev shell with `cargo` and configured PHP dependencies
rust-rover . # start the IDE (I personally prefer this one)
nix build # produces the output you want from this flake

# verify it:
echo "extension=result/lib/libexperimenting_with_rust_php_extensions.so" > ./php.ini
php -c ./php.ini -r "echo my_custom_extension('testing');";
```

Try it out (interactive shell):

```sh
nix develop
cargo build
php -c php-extension-test.ini -r "echo my_custom_extension('testing');"
```

To use this extension, like with other
[php extensions with nixos](https://wiki.nixos.org/wiki/PHP#Setting_custom_plugins_and_php.ini_configurations),
include this flake:

```
{
  description = "your flake description";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    dummy-extension = {
      url = "github:ocramius/experimenting-with-rust-php-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    }
  };
  
  outputs = { nixpkgs, dummy-extension }:
  {
    my-output = let 
      my-php-flavor = pkgs.php.buildEnv {
        extensions = ({ enabled, all }: enabled ++ [dummy-extension])
      };
    in {
      # use my-php-flavor as a package somewhere here
    };
  };
}
```

## Notes (ramblings while I was working on this stuff)

* Read about it here:
    * https://old.reddit.com/r/PHP/comments/1o9rgkv/surprisingly_easy_extension_development_in_rust/
    * https://ext-php.rs/
* let's spin up an environment here
    * want to use the rust toolchain I built elsewhere
        * [oci-srm-server-mock flake](https://github.com/Ocramius/oci-srm-server-mock-rust/blob/b0d496cffb5e2ee884bb830bc72fb984b0b19bfc/flake.nix)
* ```sh
  nix develop
  ```
* according to the docs, we'll need `php-dev`/`php-devel`
    * there's no such package on https://search.nixos.org/?
    * we may need to pull in the php source package from Nixos
* let's focus on building the flake first
    * got something semi-built
* first failure
    * ```
      --- stderr
      Error: Could not find `php-config` executable. Please ensure `php-config` is in your PATH or the `PHP_CONFIG` environment variable is set.
      ```
        * that's from `php-dev` missing
* how is PHP built in Nixos?
    * https://github.com/NixOS/nixpkgs/blob/98ff3f9af2684f6136c24beef08f5e2033fc5389/pkgs/development/interpreters/php/generic.nix#L393
        * `$dev` mentioned
            * `phpize` and `php-dev` are removed from it before finishing the build
        * perhaps we can override `postFixup`, and skip it entirely?
            * that would preserve `php-config` and `phpize`
* other extension built in PHP?
    * https://github.com/NixOS/nixpkgs/blob/98ff3f9af2684f6136c24beef08f5e2033fc5389/pkgs/development/php-packages/imap/default.nix
        * there's a `buildPecl` function
            * https://github.com/NixOS/nixpkgs/blob/c9e6d4f99f4a2c715f8e8ff369016150f982c99c/pkgs/top-level/php-packages.nix#L63
            * ```
              packages.x86_64-linux.foo = pkgs.php.unwrapped; # produces `result` and `result-dev`
              ```
                * adding that (and `php`) to `devShells` works!
* next failure
    * ```
      Unable to find libclang: "couldn't find any valid shared libraries matching: ['libclang.so', 'libclang-*.so', 'libclang.so.*', 'libclang-*.so.*'], set the `LIBCLANG_PATH` environment variable to a path where one of these files can be found (invalid: [])"
      ```
        * adding `pkgs.libclang`
            * actually `pkgs.lvmPackages.libclang.lib`
                * https://github.com/NixOS/nixpkgs/issues/52447#issuecomment-852079285
    * ```
      /nix/store/0sdngkbml3hahbchify5pbfpi2q46xsj-php-8.4.13-dev/include/php/main/../main/php_config.h:2219:10: fatal error: 'stdlib.h' file not found
      Error: Unable to generate bindings for PHP
      ```
        * https://github.com/NixOS/nixpkgs/issues/52447#issuecomment-853429315
            * added `BINDGEN_EXTRA_CLANG_ARGS`
                * no effect
        * https://discourse.nixos.org/t/stdlib-h-no-such-file-or-directory/20326
            * very much related
        * https://github.com/NixOS/nixpkgs/issues/214524
            * ```nix
              pkgs.llvmPackages.clang
              pkgs.llvmPackages.libcxx
              ```
                * actually worked / compiled!
* how to load the compiled extension?
    * ```console
      ❯ php -z ./target/debug/libexperimenting_with_rust_php_extensions.so -r "var_dump('hi');"
      ./target/debug/libexperimenting_with_rust_php_extensions.so doesn't appear to be a valid Zend extension
      string(2) "hi"
      ```
    * let's write a `php.ini`?
        * ```console
          php -c php-extension-test.ini -m
          [PHP Modules]
          Core
          date
          experimenting-with-rust-php-extensions
          <snip>
          ```
        * ```console
          ❯ php -c php-extension-test.ini -r "var_dump(my_custom_extension('testing'));"
          string(34) "From my custom extension: testing!"
          ```
* it now works with `cargo build` in `devShell`
    * let's formalize it in `built` (`default` output)
    * use `buildInputs` or `nativeBuildInputs`?
        * https://discourse.nixos.org/t/use-buildinputs-or-nativebuildinputs-for-nix-shell/8464
            * `buildInputs` = platform specific + linked against
            * `nativeBuildInput` = build-only
    * need to expand `PATH` with `php` and `php-config`
        * https://old.reddit.com/r/NixOS/comments/nuim9q/how_do_i_add_a_binary_created_with_nixbuld_to_my/
        * naersk uses `mkDerivation`
            * https://github.com/nix-community/naersk/blob/0e72363d0938b0208d6c646d10649164c43f4d64/build.nix#L605
                * how do I set PATH in `mkDerivation`?
    * problem: `pkgs.php.unwrapped` still points at the `pkgs.php` path!
        * how do I see all attributes of a nix value?
            * https://unix.stackexchange.com/questions/720895/how-to-print-all-available-attributes-of-a-nix-expression
                * need to cast it to a string
                    * ```sh
                      nix eval --impure --expr "let pkgs = import <nixpkgs> {}; in pkgs.lib.attrNames (pkgs.php.unwrapped)"
                      ```
        * I only guessed `pkgs.php.unwrapped.dev`
            * and that worked!
    * got a build running
        * but doesn't copy `lib/`?
            * `copyLibs` needed
                * https://github.com/nix-community/naersk/blob/0e72363d0938b0208d6c646d10649164c43f4d64/README.md#buildpackages-parameters
* how do we test all this together?
    * general idea:
        1. simple test that verifies `php -c some-ini-file.ini -r "var_dump(my_custom_extension('testing'));"`
        2. install the extension into a base `pkgs.php`, then run that
    * let's try following the `checks` output from https://nixos.wiki/wiki/flakes
        * https://msfjarvis.dev/posts/writing-your-own-nix-flake-checks/
    