#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="$root/build/tools"
mkdir -p "$target"

arch="$(uname -m)"
if [[ "$arch" != arm64 && "$arch" != x86_64 ]]; then
  echo "Unsupported macOS architecture: $arch" >&2
  exit 1
fi

yt_version="2026.08.19"
yt_base="https://github.com/yt-dlp/yt-dlp/releases/download/$yt_version"
curl --fail --location --retry 5 "$yt_base/yt-dlp_macos" -o "$target/yt-dlp"
expected="$(curl --fail --location --retry 5 "$yt_base/SHA2-256SUMS" | awk '$2 == "yt-dlp_macos" || $2 == "*yt-dlp_macos" { print $1 }')"
actual="$(shasum -a 256 "$target/yt-dlp" | awk '{ print $1 }')"
if [[ -z "$expected" || "$actual" != "$expected" ]]; then
  echo "yt-dlp checksum mismatch" >&2
  exit 1
fi

python3 -m venv "$root/.macos-venv"
python_bin="$root/.macos-venv/bin/python"
"$python_bin" -m pip install --upgrade 'gallery-dl==1.32.13' 'pyinstaller>=6,<7'
"$python_bin" -m PyInstaller --clean --noconfirm --onefile --collect-all gallery_dl \
  --name gallery-dl --distpath "$target" --workpath "$root/.macos-pyinstaller" \
  --specpath "$root/.macos-pyinstaller" "$root/scripts/gallery_dl_launcher.py"

cargo build --release --locked --manifest-path "$root/TorrentHelper/Cargo.toml"
cp "$root/TorrentHelper/target/release/mochidrop-torrent" "$target/mochidrop-torrent"
chmod +x "$target/yt-dlp" "$target/gallery-dl" "$target/mochidrop-torrent"

for binary in "$target/yt-dlp" "$target/gallery-dl" "$target/mochidrop-torrent"; do
  lipo -archs "$binary" | grep -qw "$arch"
done
"$target/yt-dlp" --version
"$target/gallery-dl" --version
"$target/gallery-dl" --list-extractors | grep -qi mangadex
"$target/mochidrop-torrent" --version
