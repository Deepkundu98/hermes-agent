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
# Avoid "pip download --no-binary": pip runs PEP517 on the sdist before we can patch.
# Ref: https://github.com/giampaolo/psutil/issues/2611
install_psutil_for_termux() {
	echo -e "${GRN}🔧 Building psutil with Android/Termux platform patch...${RST}"
	local _tmp="${TMPDIR:-/tmp}/hermes-psutil-build.$$"
	mkdir -p "$_tmp"
	trap 'rm -rf "$_tmp"' RETURN
	local _cfile=""
	if [ -f constraints-termux.txt ]; then
		_cfile="constraints-termux.txt"
	fi
	python - "$_tmp" "$_cfile" <<'PYFETCH'
import json
import re
import sys
import urllib.request
from pathlib import Path


def numerics(v: str) -> tuple:
	base = re.split(r"[+\-]", v, maxsplit=1)[0]
	parts = [int(x) for x in re.findall(r"\d+", base)[:4]]
	while len(parts) < 4:
		parts.append(0)
	return tuple(parts)


def in_range(v: str) -> bool:
	if not re.match(r"^\d+(\.\d+)*", v.strip().split("+")[0]):
		return False
	t = numerics(v)
	return t >= (5, 9, 0, 0) and t < (8, 0, 0, 0)


def pick_url(data, pinned=None):
	rel = data["releases"]
	if pinned:
		files = rel.get(pinned) or []
		files = [
			u
			for u in files
			if u.get("packagetype") == "sdist" and not u.get("yanked")
		]
		if not files:
			sys.exit(f"No sdist for pinned psutil=={pinned}")
		u = files[0]
		return u["url"], u["filename"], pinned

	cands = []
	for ver, files in rel.items():
		if not in_range(ver):
			continue
		for u in files:
			if u.get("packagetype") == "sdist" and not u.get("yanked"):
				cands.append((numerics(ver), ver, u["url"], u["filename"]))
				break
	if not cands:
		sys.exit("No psutil sdist found for range >=5.9,<8")
	cands.sort(key=lambda x: x[0], reverse=True)
	_, ver, url, fn = cands[0]
	return url, fn, ver


def main():
	dest = Path(sys.argv[1])
	cpath = sys.argv[2] if len(sys.argv) > 2 else ""
	pinned = None
	if cpath:
		p = Path(cpath)
		if p.is_file():
			for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
				line = line.split("#", 1)[0].strip()
				if not line.lower().startswith("psutil"):
					continue
				m = re.search(r"(?i)psutil\s*==\s*([\w.+-]+)", line)
				if m:
					pinned = m.group(1).strip()
					break

	req = urllib.request.Request(
		"https://pypi.org/pypi/psutil/json",
		headers={"User-Agent": "Hermes-Termux-install/1"},
	)
	with urllib.request.urlopen(req, timeout=120) as r:
		data = json.load(r)

	url, fn, ver = pick_url(data, pinned)
	out = dest / "psutil-src.tar.gz"

	req2 = urllib.request.Request(
		url,
		headers={"User-Agent": "Hermes-Termux-install/1"},
	)
	with urllib.request.urlopen(req2, timeout=300) as r2:
		out.write_bytes(r2.read())

	sys.stderr.write(f"Downloaded psutil {ver} ({fn})\n")


if __name__ == "__main__":
	main()
PYFETCH
	local _tar="${_tmp}/psutil-src.tar.gz"
	if [ ! -f "$_tar" ]; then
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
	python -m pip install --no-build-isolation "$_dir"
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
