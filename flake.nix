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
          # Flutter expects compileSdk=36 / build-tools=36.0.0 / ndk=28.2.13676358,
          # while plugins pin additional SDK levels (jni=35, flutter_local_notifications=37.0).
          platformVersions = ["35" "36" "37.0"];
          buildToolsVersions = ["35.0.0" "36.0.0" "37.0.0"];
          platformToolsVersion = "latest";
          cmdLineToolsVersion = "latest";
          cmakeVersions = ["3.22.1"];
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
          pkgs.libsecret
          pkgs.json-glib
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
