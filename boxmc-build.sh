#!/usr/bin/env bash
# boxmc-build.sh — reproducible BINARY-PATCH build of QuickShop-Hikari for BoxMC (BUG-0655).
#
# Input : the exact upstream jar BoxMC runs, QuickShop-Hikari-6.3.0.0-SNAPSHOT-12.jar
#         (upstream commit 2a67c8f94b9f1aa06dde8093028a29b30b4f0010, per the jar's own BUILDINFO),
#         sha256 b7ea124cc2bf10dedc2a436482009008f2e1c2301c967d613f39071601d6ba58, 4,691,983 bytes.
# Output: QuickShop-Hikari-6.3.0.0-SNAPSHOT-12-boxmc.1.jar = that jar with ONLY
#         com/ghostchu/quickshop/api/command/CommandHandler.class replaced by the one compiled from this branch.
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
SRC=quickshop-api/src/main/java/com/ghostchu/quickshop/api/command/CommandHandler.java
CLS=com/ghostchu/quickshop/api/command/CommandHandler.class
mkdir -p "$OUT"; WORK=$(mktemp -d); trap 'rm -f "$WORK"/classes/$CLS; rmdir -p "$WORK"/classes/com/ghostchu/quickshop/api/command 2>/dev/null || true' EXIT
mkdir -p "$WORK/classes"
# The deployed classes are major version 65 (Java 21): compile to the same level.
javac --release 21 -nowarn -proc:none -cp "$CP:$UP" -d "$WORK/classes" "$HERE/$SRC"
# A compile of this one file must produce exactly this one class (no nested/anonymous classes).
N=$(cd "$WORK/classes" && find . -name '*.class' | wc -l)
[ "$N" = 1 ] || { echo "expected 1 compiled class, got $N" >&2; exit 1; }
JAR="$OUT/QuickShop-Hikari-6.3.0.0-SNAPSHOT-12-boxmc.1.jar"
cp "$UP" "$JAR"
(cd "$WORK/classes" && zip -q "$JAR" "$CLS")
echo "built $JAR  $(stat -c %s "$JAR") B  sha256 $(sha256sum "$JAR" | cut -d' ' -f1)"
