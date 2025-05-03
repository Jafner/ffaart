# FFAART: Fidelity-First Automagical AV1 Reencoding to Target

An intelligent video transcoding utility that prioritizes perceptual quality while leveraging AV1 to reduce file sizes with minimal user input.

```sh
ffaart [--bitrate B] [--resolution X Y] [--framerate F] [--keep-original] [--dry-run] input.mp4
```

## Features

- Reduces video size while preserving perceptual quality.
- Sane defaults for resolution, framerate, and bitrate.

## Installation

### Install on Nix/OS
Add this flake to your `flake.nix`:
```nix
inputs.ffaart.url = "github:Jafner/ffaart";
```

Add the package to your nixosConfiguration:
```nix
environment.systemPackages = with pkgs; [
  ffaart
];
# Or
home-manager.users.${username}.home.packages = [
  inputs.ffaart.default
];
```

### Temporarily install via Nix shell
```nix
nix shell github:Jafner/ffaart
```

### Manual
1. Ensure `ffmpeg` is installed.
2. Download the script and make it executable from your path:
```sh
wget -O ~/.local/bin/ffaart https://raw.githubusercontent.com/Jafner/ffaart/main/ffaart.sh
chmod +x ~/.local/bin/ffaart
```

## Usage

### Options
- `--bitrate <bitrate>`: Target bitrate (default: auto-calculated)
- `--resolution <width> <height>`: Target resolution (default: source resolution)
- `--framerate <fps>`: Target frame rate (default: source frame rate)
- `--keep-original`: Keep original file (default: false)
- `--dry-run`: Show command to run without executing

### Using `nix run`
```sh
nix run github:Jafner/ffaart -- [--bitrate B] [--resolution X Y] [--framerate F] [--keep-original] [--dry-run] input.mp4
```

## Output
1. **Replaces original file** with new, `mp4`-contained, `av1`-encoded file in the same directory as the input.
  - If `--keep-original` is specified, the original file is kept as `${INPUT_FILE_PATH%.*}.original.${INPUT_FILE_PATH##*.}`.
    E.g. `/home/user/Videos/MyVideo.original.mkv` (original extension is preserved.)
2. **Logs** the result of the run to stdout in structured json.

E.g.
```sh
$ ffaart --bitrate 4M --resolution 1920 1080 "$HOME/Videos/MyVideo.mp4"
```

## Dependencies
- ffmpeg (with AV1, VAAPI support)
- Hardware accelerator that supports VAAPI & AV1 at `/dev/dri/renderD128`
- nix (optional)

## License
[MIT](LICENSE)
