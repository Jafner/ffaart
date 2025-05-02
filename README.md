# FFAART: Fidelity-First Automagical AV1 Reencoding to Target

An intelligent video transcoding utility that prioritizes perceptual quality while leveraging AV1 to reduce file sizes with minimal user input.

## Features

- Reduces video size while preserving perceptual quality.
- Automatically determines resolution, framerate, and bitrate.
- Supports explicitly specified resolution, framerate, and bitrate.

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

```sh
ffaart [--bitrate B] [--resolution X Y] [--framerate F] [--dry-run] input.mp4
```

### Options
- `--bitrate <bitrate>`: Target bitrate (default: auto-calculated)
- `--resolution <width> <height>`: Target resolution (default: source resolution)
- `--framerate <fps>`: Target frame rate (default: source frame rate)
- `--dry-run`: Show commands without executing

### Using `nix run`
```sh
nix run github:Jafner/ffaart -- [--bitrate B] [--resolution X Y] [--framerate F] [--dry-run] input.mp4
```

## Output
Creates a new file with `.av1.mp4` suffix in the same directory as the input.

E.g.
```sh
$ ffaart --bitrate 4M --resolution 1920 1080 --framerate 60 "$HOME/Videos/MyVideo.mp4"
Target resolution defaulting to source resolution: 2560 x 1440
Target framerate defaulting to source framerate: 60/1
```

## Dependencies
- nix
- ffmpeg-full (with AV1 support)

## License
[MIT](LICENSE)
