{
  description = "Development environments for pi-furry-partner";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          node = pkgs.nodejs_24;
          mkSitePackage = { pname, version, projectDir }:
            pkgs.stdenvNoCC.mkDerivation {
              inherit pname version;
              src = self;
              nativeBuildInputs = [ node ];
              dontConfigure = true;

              buildPhase = ''
                runHook preBuild
                sourceDir="$NIX_BUILD_TOP/$sourceRoot"
                cd "$sourceDir/${projectDir}"
                npm run build:site
                npm run test:site
                runHook postBuild
              '';

              installPhase = ''
                runHook preInstall
                mkdir -p "$out"
                sourceDir="$NIX_BUILD_TOP/$sourceRoot"
                cp -R "$sourceDir/${projectDir}/dist/." "$out/"
                runHook postInstall
              '';
            };
        in
        {
          pi-original-runtime =
            let runtimeVersion = "2.5.1";
            in pkgs.stdenvNoCC.mkDerivation {
            pname = "pi-furry-partner-runtime";
            version = runtimeVersion;
            src = self;
            nativeBuildInputs = [ node pkgs.gnutar ];
            dontConfigure = true;

            buildPhase = ''
              runHook preBuild
              export HOME="$NIX_BUILD_TOP/home"
              export npm_config_cache="$NIX_BUILD_TOP/npm-cache"
              mkdir -p "$HOME" "$npm_config_cache"
              sourceDir="$NIX_BUILD_TOP/$sourceRoot"
              cd "$sourceDir"
              npm pack --ignore-scripts --pack-destination "$NIX_BUILD_TOP"
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p "$out"
              tar -xzf "$NIX_BUILD_TOP/pi-furry-partner-${runtimeVersion}.tgz" \
                --strip-components=1 --directory "$out"
              runHook postInstall
            '';
          };

          site-original = mkSitePackage {
            pname = "pi-furry-partner-site-original";
            version = "2.5.1";
            projectDir = ".";
          };

          site-hd = mkSitePackage {
            pname = "pi-furry-partner-site-hd";
            version = "2.5.1-preview.6";
            projectDir = "editions/hd";
          };
        });

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          node = pkgs.nodejs_24;
          pythonWithValidation = pkgs.python3.withPackages (pythonPackages: [
            pythonPackages.numpy
            pythonPackages.pillow
          ]);

          # The project tests consume a node_modules directory, not the Pi
          # launcher. Until the npm dependency closures are locked as Nix
          # packages, these shells bootstrap the exact CI-style runtime into
          # the ignored work/ directory and then reuse it on later entries.
          mkPiShell = { version, runtimeName }:
            pkgs.mkShell {
              packages = [
                node
                pkgs.git
              ];

              shellHook = ''
                export PI_TEST_MODULES="$PWD/work/${runtimeName}/node_modules"
                runtime_package="$PI_TEST_MODULES/@earendil-works/pi-coding-agent/package.json"
                tui_package="$PI_TEST_MODULES/@earendil-works/pi-tui/package.json"
                if [ ! -f "$runtime_package" ] || [ ! -f "$tui_package" ] \
                  || [ "$(node -p 'require(process.argv[1]).version' "$runtime_package")" != "${version}" ] \
                  || [ "$(node -p 'require(process.argv[1]).version' "$tui_package")" != "${version}" ]; then
                  echo "Installing Pi test runtime ${version} into $PWD/work/${runtimeName}"
                  mkdir -p "$PWD/work/${runtimeName}"
                  npm install \
                    --prefix "$PWD/work/${runtimeName}" \
                    --no-save --no-package-lock --no-audit --no-fund \
                    "@earendil-works/pi-coding-agent@${version}" \
                    "@earendil-works/pi-tui@${version}"
                fi
                echo "PI_TEST_MODULES=$PI_TEST_MODULES"
                echo "Pi ${version} runtime is ready for: npm test"
              '';
            };
        in
        {
          # Root original-resource development. Pi's real runtime remains an
          # explicit local/CI test input rather than an unpinned npm install.
          default = pkgs.mkShell {
            packages = [
              node
              pkgs.python3
              pkgs.coreutils
              pkgs.gh
              pkgs.git
              pkgs.unzip
            ];

            shellHook = ''
              echo "pi-furry-partner original-resource development shell"
              echo "Suggested checks: npm test; npm run build:site; npm run test:site"
              echo "Pi runtime tests additionally require PI_TEST_MODULES."
            '';
          };

          # HD package and validation work. This deliberately does not include
          # generation-only media tooling; use the media shell for that.
          hd = pkgs.mkShell {
            packages = [
              node
              pythonWithValidation
              pkgs.git
              pkgs.gnutar
              pkgs.gzip
              pkgs.unzip
            ];

            shellHook = ''
              echo "pi-furry-partner HD development and validation shell"
              echo "Run from editions/hd: npm test; npm run build:site; npm run test:site"
              echo "Pi runtime tests additionally require PI_TEST_MODULES."
            '';
          };

          # Offline asset-production tools. Approved runtime frames remain
          # source inputs; entering this shell does not regenerate them.
          pi-1_2 = mkPiShell {
            version = "1.2.0";
            runtimeName = "pi-runtime-1.2";
          };

          pi-1_3 = mkPiShell {
            version = "1.3.0";
            runtimeName = "pi-runtime-1.3";
          };

          media = pkgs.mkShell {
            packages = [
              node
              pythonWithValidation
              pkgs.ffmpeg
              pkgs.libwebp
              pkgs.git
            ];

            shellHook = ''
              echo "pi-furry-partner offline media-production shell"
              echo "Read editions/hd/docs/production/AGENTS.md before changing assets."
            '';
          };
        });

      formatter = forAllSystems (system:
        (import nixpkgs { inherit system; }).nixfmt-rfc-style);
    };
}
