{
  description = "Fidelity-First Automagical AV1 Reencode to Target";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };
  outputs = inputs@{ self, nixpkgs, ... }: {
    apps.x86_64-linux = {
      default = self.apps.ffaart;
      ffaart = {
        type = "app";
        program = "${self.packages."x86_64-linux".ffaart.outPath}/bin/${self.packages."x86_64-linux".ffaart.meta.mainProgram}";
      };
      test = {
        type = "app";
        program = "${self.packages."x86_64-linux".ffaart-test.outPath}/bin/${self.packages."x86_64-linux".ffaart-test.meta.mainProgram}";
      };
      ffmpeg = {
        type = "app";
        program = "${nixpkgs.legacyPackages."x86_64-linux".ffmpeg-full.outPath}/bin/${nixpkgs.legacyPackages."x86_64-linux".ffmpeg-full.meta.mainProgram}";
      };
    };
    packages.x86_64-linux = {
      default = self.packages."x86_64-linux".ffaart;
      ffaart = (inputs.nixpkgs.legacyPackages."x86_64-linux".writeShellApplication {
        name = "ffaart";
        runtimeInputs = [
          inputs.nixpkgs.legacyPackages."x86_64-linux".ffmpeg-full
          inputs.nixpkgs.legacyPackages."x86_64-linux".jq
        ];
        text = builtins.readFile ./ffaart.sh;
      });
      ffaart-test = (inputs.nixpkgs.legacyPackages."x86_64-linux".writeShellApplication {
        name = "ffaart-test";
        runtimeInputs = [
          inputs.nixpkgs.legacyPackages."x86_64-linux".ffmpeg-full
          inputs.nixpkgs.legacyPackages."x86_64-linux".jq
        ];
        text = builtins.readFile ./test.sh;
      });
    };
    devShells."x86_64-linux".default = import ./shell.nix { pkgs = inputs.nixpkgs.legacyPackages."x86_64-linux"; };
  };
}
