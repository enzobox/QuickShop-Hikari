#!/usr/bin/env bash
# boxmc-build.sh — reproducible BINARY-PATCH build of QuickShop-Hikari for BoxMC (BUG-0655).
#
# Input : the exact upstream jar BoxMC runs, QuickShop-Hikari-6.3.0.0-SNAPSHOT-12.jar
#         (upstream commit 2a67c8f94b9f1aa06dde8093028a29b30b4f0010, per the jar's own BUILDINFO),
#         sha256 b7ea124cc2bf10dedc2a436482009008f2e1c2301c967d613f39071601d6ba58, 4,691,983 bytes.
# Output: QuickShop-Hikari-6.3.0.0-SNAPSHOT-12-boxmc.2.jar = that jar with ONLY the classes compiled from the
#         patched sources below replaced (boxmc.1 = CommandHandler only; boxmc.2 adds BlockListener + SubCommand_Staff):
#           com/ghostchu/quickshop/api/command/CommandHandler.class            (BUG-0655 unscaled-eye fallback)
#           com/ghostchu/quickshop/command/subcommand/SubCommand_Staff.class   (/qs staff uses that fallback after a miss)
#           com/ghostchu/quickshop/listener/BlockListener.class                (2nd hit within 10 s on a shop SIGN = remove)
#           com/ghostchu/quickshop/listener/PlayerListener.class (+ $ClickType) (2nd hit within 10 s is not a trade/cancel)
#
# Why a binary patch and not a full reactor build: the full build re-shades ~20 libraries and stamps new
# timestamps/BUILDINFO, so every byte of the jar would differ from what has run on production since 2026-08-01.
# Replacing one class keeps the tested artifact and makes the diff exactly the patched source file.
#
# Usage: ./boxmc-build.sh <upstream-jar> <outdir> <compile-classpath>
#   compile-classpath = colon-separated: org.jetbrains:annotations 26.x, dev.folia:folia-api 26.2 (or paper-api), and
#   net.kyori adventure-api/adventure-key 5.2.0 + examination-api + option. It is placed BEFORE the upstream jar because
#   that jar shades an old org.jetbrains.annotations without TYPE_USE, which then fails on CommandHandler's type annotations.
set -euo pipefail
UP=${1:?upstream jar}; OUT=${2:?outdir}; CP=${3:?compile classpath}
WANT=b7ea124cc2bf10dedc2a436482009008f2e1c2301c967d613f39071601d6ba58
GOT=$(sha256sum "$UP" | cut -d' ' -f1)
[ "$GOT" = "$WANT" ] || { echo "REFUSING: input jar sha256 $GOT != $WANT" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
SRCS=(quickshop-api/src/main/java/com/ghostchu/quickshop/api/command/CommandHandler.java
      quickshop-bukkit/src/main/java/com/ghostchu/quickshop/command/subcommand/SubCommand_Staff.java
      quickshop-bukkit/src/main/java/com/ghostchu/quickshop/listener/BlockListener.java
      quickshop-bukkit/src/main/java/com/ghostchu/quickshop/listener/PlayerListener.java)
CLSS=(com/ghostchu/quickshop/api/command/CommandHandler.class
      com/ghostchu/quickshop/command/subcommand/SubCommand_Staff.class
      com/ghostchu/quickshop/listener/BlockListener.class
      com/ghostchu/quickshop/listener/PlayerListener.class
      'com/ghostchu/quickshop/listener/PlayerListener$ClickType.class')
mkdir -p "$OUT"; WORK=$(mktemp -d)
trap 'for c in "${CLSS[@]}"; do rm -f "$WORK/classes/$c"; done; for src in "${SRCS[@]}"; do rm -f "$WORK/src/$src"; done; find "$WORK" -depth -type d -empty -delete 2>/dev/null || true' EXIT
mkdir -p "$WORK/classes"
# The upstream build SHADES and RELOCATES some libraries (pom.xml maven-shade relocations), so a source compiled against
# the jar must use the relocated names. Mirror the one relocation the patched sources need (net.tnemc -> ...shade.tne,
# PlayerListener's MenuManager) in a temp copy, and refuse if a patched source touches any other relocated package.
mkdir -p "$WORK/src"; SRCFILES=()
for src in "${SRCS[@]}"; do
  if command grep -a -n -E '\b(cc\.carm\.lib|com\.tcoded|io\.papermc\.lib\.|de\.tr7zw\.changeme\.nbtapi|org\.bstats|de\.themoep\.minedown\.|com\.alessiodp\.libby\.|com\.mohistmc\.)' "$HERE/$src"; then
    echo "REFUSING: $src uses a relocated package this script does not mirror" >&2; exit 1
  fi
  mkdir -p "$WORK/src/$(dirname "$src")"
  sed -E 's/\bnet\.tnemc\./com.ghostchu.quickshop.shade.tne./g' "$HERE/$src" > "$WORK/src/$src"
  SRCFILES+=("$WORK/src/$src")
done
# The deployed classes are major version 65 (Java 21): compile to the same level.
javac --release 21 -nowarn -proc:none -cp "$CP:$UP" -d "$WORK/classes" "${SRCFILES[@]}"
# The compile must produce exactly these classes (no nested/anonymous classes the jar does not already have).
N=$(cd "$WORK/classes" && find . -name '*.class' | wc -l)
[ "$N" = "${#CLSS[@]}" ] || { echo "expected ${#CLSS[@]} compiled classes, got $N" >&2; exit 1; }
for c in "${CLSS[@]}"; do [ -f "$WORK/classes/$c" ] || { echo "missing compiled $c" >&2; exit 1; }; unzip -l "$UP" "$c" >/dev/null || { echo "$c is not in the upstream jar" >&2; exit 1; }; done
JAR="$OUT/QuickShop-Hikari-6.3.0.0-SNAPSHOT-12-boxmc.2.jar"
cp "$UP" "$JAR"
(cd "$WORK/classes" && zip -q "$JAR" "${CLSS[@]}")
echo "built $JAR  $(stat -c %s "$JAR") B  sha256 $(sha256sum "$JAR" | cut -d' ' -f1)"
