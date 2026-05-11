#!/bin/bash

# Hermes Agent - One-line installer for Termux (Android)
# Usage: curl -fsSL https://your-raw-url/hermes_install.sh | bash

set -e

GRN='\033[0;32m'
CYN='\033[0;36m'
YEL='\033[0;33m'
RST='\033[0m'

export DEBIAN_FRONTEND=noninteractive

echo -e "${CYN}=====================================================${RST}"
echo -e "${GRN}                   THEVOIDKERNEL"
echo -e "${CYN}=====================================================${RST}"

echo -e "${CYN}=====================================================${RST}"
echo -e "${GRN}        🚀 Installing Hermes Agent on Termux..."
echo -e "${CYN}=====================================================${RST}"

echo "📦 Repository: https://github.com/AbuZar-Ansarii/Hermes-Agent-On-Android"

# Update packages (noninteractive where supported)
pkg update -y -o Dpkg::Options::="--force-confnew" 2>/dev/null || pkg update -y
pkg upgrade -y 2>/dev/null || true

# Install dependencies
pkg install -y git python clang rust make pkg-config libffi openssl nodejs ripgrep ffmpeg

# Clone repository
rm -rf hermes-agent 2>/dev/null || true
git clone --recurse-submodules https://github.com/NousResearch/hermes-agent.git

# Navigate to directory
cd hermes-agent

# Setup Python virtual environment
python -m venv venv
# shellcheck source=/dev/null
source venv/bin/activate

# Set Android API level
export ANDROID_API_LEVEL="$(getprop ro.build.version.sdk 2>/dev/null || echo 24)"

# Upgrade pip tools
python -m pip install --upgrade pip setuptools wheel

# PATCH: psutil's setup.py exits with "platform android is not supported" on Termux.
# Apply the same change as Termux's python-psutil package: treat android like linux.
# Ref: https://github.com/giampaolo/psutil/issues/2611
install_psutil_for_termux() {
	echo -e "${GRN}🔧 Building psutil with Android/Termux platform patch...${RST}"
	local _tmp="${TMPDIR:-/tmp}/hermes-psutil-build.$$"
	mkdir -p "$_tmp"
	trap 'rm -rf "$_tmp"' RETURN
	local _dl=( -m pip download 'psutil>=5.9.0,<8' --no-binary :all: --no-deps -d "$_tmp" )
	if [ -f constraints-termux.txt ]; then
		python "${_dl[@]}" -c constraints-termux.txt
	else
		python "${_dl[@]}"
	fi
	local _tar
	_tar="$(find "$_tmp" -maxdepth 1 -name 'psutil-*.tar.gz' ! -name '*.asc' | head -1)"
	if [ -z "$_tar" ]; then
		echo -e "${YEL}❌ Could not download psutil source archive.${RST}" >&2
		exit 1
	fi
	tar -xzf "$_tar" -C "$_tmp"
	local _dir
	_dir="$(find "$_tmp" -maxdepth 1 -type d -name 'psutil-*' | head -1)"
	local _common="${_dir}/psutil/_common.py"
	if [ ! -f "$_common" ]; then
		echo -e "${YEL}❌ psutil/_common.py not found in extracted source.${RST}" >&2
		exit 1
	fi
	python - "$_common" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
already = 'LINUX = sys.platform.startswith(("linux", "android"))'
if already in text:
	sys.exit(0)
old = 'LINUX = sys.platform.startswith("linux")'
if old not in text:
	sys.stderr.write(
		"Cannot patch psutil: expected LINUX line not found in _common.py\n"
	)
	sys.exit(1)
path.write_text(text.replace(old, already, 1), encoding="utf-8")
PY
	python -m pip install "$_dir"
}

install_psutil_for_termux

# Install Hermes with Termux support
python -m pip install -e '.[termux]' -c constraints-termux.txt

# Create global symlink
ln -sf "$PWD/venv/bin/hermes" "$PREFIX/bin/hermes"

echo "✅ Hermes Agent installed successfully!"
echo "🔥 Run 'hermes' or 'hermes setup' to start using it"
echo "📖 Type 'hermes --help' for more options"
echo ""
echo "💡 Need help? Visit: https://github.com/AbuZar-Ansarii/Hermes-Agent-On-Android"
echo ""

echo "🌐 Run 'hermes gateway' to run deply it"
