#!/usr/bin/env bash
# Builds LAME (LGPL) as a static arm64 iOS library into Vendor/lame
set -euo pipefail
VER=3.100
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Vendor/lame"
WORK="$(mktemp -d)"
curl -fL "https://downloads.sourceforge.net/project/lame/lame/$VER/lame-$VER.tar.gz" -o "$WORK/lame.tgz"
tar -xzf "$WORK/lame.tgz" -C "$WORK"
cd "$WORK/lame-$VER"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CC="$(xcrun --sdk iphoneos -f clang)"
FLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=16.0 -O3"
./configure --host=arm-apple-darwin --prefix="$OUT" \
  --disable-shared --enable-static --disable-frontend --disable-decoder \
  CC="$CC" CFLAGS="$FLAGS -DHAVE_MEMCPY -include strings.h" LDFLAGS="$FLAGS"
make -j"$(sysctl -n hw.ncpu)"
make install
echo "LAME installed to $OUT"
