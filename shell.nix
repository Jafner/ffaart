{ pkgs, ... }: pkgs.mkShell {
  buildInputs = [
    pkgs.ffmpeg-full
    pkgs.imagemagick
    pkgs.hyperfine
    pkgs.jq
  ];
}
