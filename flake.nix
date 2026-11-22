{
  description = "YATA - Yet Another Todo App";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

    devShells = forAllSystems (system: let
      pkgs = import nixpkgs {
        inherit system;
        config = {
          android_sdk.accept_license = true;
          allowUnfree = true;
        };
      };

      androidSdk =
        (pkgs.androidenv.composeAndroidPackages {
          # Pinned to the versions Flutter expects (see flutter_tools FlutterExtension.kt):
          # compileSdk=36, build-tools=36.0.0, ndk=28.2.13676358
          platformVersions = ["36"];
          buildToolsVersions = ["36.0.0"];
          platformToolsVersion = "latest";
          cmdLineToolsVersion = "latest";
          ndkVersions = ["28.2.13676358"];
          includeEmulator = false;
          includeNDK = true;
        }).androidsdk;

      sdkPath = "${androidSdk}/libexec/android-sdk";
      jdk = pkgs.jdk17;
    in {
      default = pkgs.mkShell {
        packages = [
          pkgs.flutter
          jdk
          androidSdk
          pkgs.android-tools
          pkgs.git
          pkgs.pkg-config
          pkgs.libunwind
          pkgs.orc
          pkgs.libsysprof-capture
          pkgs.pcre2.dev
          pkgs.elfutils.dev
          pkgs.zstd.dev
          pkgs.gst_all_1.gstreamer
          pkgs.gst_all_1.gstreamer.dev
          pkgs.gst_all_1.gst-plugins-base
          pkgs.gst_all_1.gst-plugins-base.dev
          pkgs.gst_all_1.gst-plugins-good
          pkgs.gst_all_1.gst-plugins-ugly
        ];

        JAVA_HOME = "${jdk}";
        ANDROID_HOME = sdkPath;
        ANDROID_SDK_ROOT = sdkPath;

        shellHook = ''
          export PATH="$ANDROID_HOME/platform-tools:$PATH"
        '';
      };
    });
  };
}
