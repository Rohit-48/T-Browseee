{
  description = "t-browsee — a CLI search tool that answers queries in your terminal using web search + LLM synthesis";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, rust-overlay, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; };

        # Pin to stable Rust. Switch to `rust-overlay.packages.${system}.rust-nightly`
        # if you need nightly features.
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" "clippy" "rustfmt" ];
        };

        # Read package metadata directly from Cargo.toml so version is never duplicated.
        cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
        inherit (cargoToml.package) name version;

        # The main package build.
        t-browsee = pkgs.rustPlatform.buildRustPackage {
          pname = name;
          inherit version;

          src = pkgs.lib.cleanSource ./.;

          cargoLock.lockFile = ./Cargo.lock;

          # Native build-time dependencies (not linked into the binary).
          nativeBuildInputs = with pkgs; [
            pkg-config
          ];

          # Runtime-linked system libraries.
          # reqwest with native-tls needs openssl; switch to rustls to drop this.
          buildInputs = with pkgs; [
            openssl
          ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            # macOS system frameworks required by the TLS stack.
            pkgs.darwin.apple_sdk.frameworks.Security
            pkgs.darwin.apple_sdk.frameworks.SystemConfiguration
          ];

          # Tell pkg-config where to find openssl on Linux.
          OPENSSL_NO_VENDOR = 1;

          # Shell completions — generated at build time and installed into the
          # right XDG locations so bash/zsh/fish pick them up automatically.
          postInstall = ''
            # Generate completions by running the compiled binary with a helper flag.
            # Requires your CLI to support: t-browsee completions <shell>
            installShellCompletion --cmd t-browsee \
              --bash <($out/bin/t-browsee completions bash) \
              --zsh  <($out/bin/t-browsee completions zsh) \
              --fish <($out/bin/t-browsee completions fish)
          '';

          meta = with pkgs.lib; {
            description = "CLI tool that answers natural language queries using web search and LLM synthesis";
            homepage    = "https://github.com/yourusername/t-browsee";
            license     = licenses.mit;
            maintainers = [ ];
            mainProgram = "t-browsee";
            platforms   = platforms.unix; # Linux + macOS; not Windows
          };
        };

      in {
        # ── Packages ─────────────────────────────────────────────────────────
        packages = {
          default     = t-browsee;
          t-browsee   = t-browsee;
        };

        # ── Apps (runnable via `nix run`) ─────────────────────────────────────
        apps.default = flake-utils.lib.mkApp {
          drv = t-browsee;
        };

        # ── Dev Shell ─────────────────────────────────────────────────────────
        # Enter with: nix develop
        devShells.default = pkgs.mkShell {
          name = "t-browsee-dev";

          packages = with pkgs; [
            rustToolchain   # compiler + analyzer + clippy + rustfmt
            pkg-config
            openssl
            openssl.dev

            # Useful dev tools
            cargo-watch     # `cargo watch -x run` for live reload
            cargo-edit      # `cargo add`, `cargo rm`, `cargo upgrade`
            cargo-nextest   # faster test runner
            hyperfine       # benchmarking: `hyperfine 't-browsee "rust borrow checker"'`
          ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            pkgs.darwin.apple_sdk.frameworks.Security
            pkgs.darwin.apple_sdk.frameworks.SystemConfiguration
          ];

          # Point pkg-config and the Rust openssl crate to the Nix-managed openssl.
          OPENSSL_NO_VENDOR = 1;
          PKG_CONFIG_PATH   = "${pkgs.openssl.dev}/lib/pkgconfig";

          shellHook = ''
            echo ""
            echo "  t-browsee dev shell"
            echo "  ───────────────────────────────────────────────────"
            echo "  cargo build          — compile"
            echo "  cargo watch -x run   — live reload (needs cargo-watch)"
            echo "  cargo test           — run tests"
            echo "  cargo nextest run    — run tests (faster)"
            echo "  cargo clippy         — lint"
            echo "  cargo fmt            — format"
            echo ""
            echo "  Config location: ~/.config/t-browsee/config.toml"
            echo ""
          '';
        };
      }
    );
}
