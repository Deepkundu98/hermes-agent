#!/bin/bash

# Hermes Agent - Termux Installer (Python 3.13 Compatible)
# Repository: https://github.com/AbuZar-Ansarii/Hermes-Agent-On-Android

set -e

GRN='\033[0;32m'
CYN='\033[0;36m'
YEL='\033[0;33m'
RST='\033[0m'

echo -e "${CYN}=====================================================${RST}"
echo -e "${GRN}         HERMES AGENT - TERMUX INSTALLER${RST}"
echo -e "${CYN}=====================================================${RST}"

# Fix apt prompts
export DEBIAN_FRONTEND=noninteractive

# Update packages first
echo -e "${GRN}📦 Updating package lists...${RST}"
pkg update -y -o Dpkg::Options::="--force-confnew" 2>/dev/null || pkg update -y

# Install Python 3.13 (current version)
echo -e "${GRN}🐍 Installing Python...${RST}"
pkg install -y python

# PATCH: Fix psutil compatibility with Python 3.13 on Termux
# This removes the unsupported compiler flag -fno-openmp-implicit-rpath
echo -e "${GRN}🔧 Patching Python sysconfig for psutil compatibility...${RST}"
_file="$(find $PREFIX/lib/python3.* -name "_sysconfigdata*.py" 2>/dev/null | head -1)"
if [ -f "$_file" ]; then
    cp "$_file" "$_file.backup"
    sed -i 's|-fno-openmp-implicit-rpath||g' "$_file"
    rm -rf $PREFIX/lib/python3.*/__pycache__
    echo -e "${GRN}✅ Python patched successfully${RST}"
else
    echo -e "${YEL}⚠️ Python sysconfig file not found, continuing...${RST}"
fi

# Install other dependencies
echo -e "${GRN}📦 Installing other dependencies...${RST}"
pkg install -y git clang rust make pkg-config libffi openssl nodejs ripgrep ffmpeg

# Clone repository
echo -e "${GRN}📥 Cloning Hermes Agent...${RST}"
rm -rf hermes-agent 2>/dev/null
git clone --recurse-submodules https://github.com/NousResearch/hermes-agent.git
cd hermes-agent

# Setup Python virtual environment
echo -e "${GRN}🐍 Setting up Python virtual environment...${RST}"
python -m venv venv
source venv/bin/activate

# Set Android API level
export ANDROID_API_LEVEL="$(getprop ro.build.version.sdk 2>/dev/null || echo 24)"

# Upgrade pip
python -m pip install --upgrade pip setuptools wheel

# PATCH: psutil refuses "android" in setup.py unless _common.py treats android like linux.
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

# Install Hermes with Termux extra
echo -e "${GRN}🔧 Installing Hermes Agent...${RST}"
python -m pip install -e '.[termux]' -c constraints-termux.txt

# Create global symlink
ln -sf "$PWD/venv/bin/hermes" "$PREFIX/bin/hermes"

echo -e "${GRN}=====================================================${RST}"
echo -e "${GRN}✅ Hermes Agent installed successfully!${RST}"
echo -e "${GRN}=====================================================${RST}"
echo ""
echo -e "${CYN}🔥 Run 'hermes' to start using it${RST}"
echo -e "${CYN}🔧 Run 'hermes setup' for configuration${RST}"
echo -e "${CYN}📖 Type 'hermes --help' for more options${RST}"
echo ""
echo -e "${GRN}💡 Need help? Visit:${RST} https://github.com/AbuZar-Ansarii/Hermes-Agent-On-Android"
