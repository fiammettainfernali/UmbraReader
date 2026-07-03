#!/usr/bin/env bash
# Downloads a diverse corpus of public-domain / openly-licensed EPUBs into
# test/corpus/ for the parser robustness test (test/epub_corpus_test.dart).
# The corpus is .gitignored — run this once locally (or in CI) before running
# the test; without the files the test skips itself.
#
# Mix:
#  - Standard Ebooks: strict modern EPUB3, semantic markup, endnotes.
#  - Project Gutenberg (via the pglaf mirror; gutenberg.org proper is often
#    unreachable from datacenter IPs): both the epub3 and legacy epub2
#    builds — messy generated markup, inline images, poetry, non-English.
#  - W3C/IDPF epub3-samples: the official EPUB3 conformance samples —
#    footnotes, SVG, MathML, right-to-left and vertical Japanese text.
set -u
cd "$(dirname "$0")/.."
mkdir -p test/corpus
cd test/corpus

fetch() { # fetch <output-name> <url>
  local out="$1" url="$2"
  # Re-fetch anything that previously saved an HTML error page.
  if [ -s "$out" ] && head -c2 "$out" | grep -q PK; then
    echo "have    $out"
    return
  fi
  if curl -fsSL --retry 2 -A 'UmbraReaderCorpus/1.0' -o "$out" "$url" \
      && head -c2 "$out" | grep -q PK; then
    echo "fetched $out"
  else
    echo "FAILED  $out ($url)" >&2
    rm -f "$out"
  fi
}

# ── Standard Ebooks (EPUB3, endnotes, semantic markup) ──────────────────────
# The bare download URL returns an HTML interstitial; ?source=download serves
# the actual file.
SE=https://standardebooks.org/ebooks
fetch se_pride-and-prejudice.epub  "$SE/jane-austen/pride-and-prejudice/downloads/jane-austen_pride-and-prejudice.epub?source=download"
fetch se_frankenstein.epub         "$SE/mary-shelley/frankenstein/downloads/mary-shelley_frankenstein.epub?source=download"
fetch se_the-time-machine.epub     "$SE/h-g-wells/the-time-machine/downloads/h-g-wells_the-time-machine.epub?source=download"
fetch se_dubliners.epub            "$SE/james-joyce/dubliners/downloads/james-joyce_dubliners.epub?source=download"
fetch se_the-art-of-war.epub       "$SE/sun-tzu/the-art-of-war/lionel-giles/downloads/sun-tzu_the-art-of-war_lionel-giles.epub?source=download"
fetch se_poetry-dickinson.epub     "$SE/emily-dickinson/poetry/downloads/emily-dickinson_poetry.epub?source=download"

# ── Project Gutenberg via the pglaf.org mirror ───────────────────────────────
PG=https://gutenberg.pglaf.org/cache/epub
fetch pg_alice-epub3.epub          "$PG/11/pg11-images-3.epub"
fetch pg_alice-epub2.epub          "$PG/11/pg11-images.epub"
fetch pg_moby-dick-epub3.epub      "$PG/2701/pg2701-images-3.epub"
fetch pg_sherlock-epub3.epub       "$PG/1661/pg1661-images-3.epub"
fetch pg_grimm-epub3.epub          "$PG/2591/pg2591-images-3.epub"
fetch pg_war-worlds-epub2.epub     "$PG/36/pg36-images.epub"
fetch pg_metamorphosis-epub2.epub  "$PG/5200/pg5200.epub"
fetch pg_french-verne.epub         "$PG/5097/pg5097-images-3.epub"
fetch pg_german-kant.epub          "$PG/6343/pg6343-images-3.epub"
fetch pg_chinese-hongloumeng.epub  "$PG/24264/pg24264-images-3.epub"

# ── W3C/IDPF EPUB3 conformance samples (GitHub) ──────────────────────────────
IDPF=https://github.com/IDPF/epub3-samples/releases/download/20170606
fetch idpf_moby-dick.epub          "$IDPF/moby-dick.epub"
fetch idpf_accessible.epub         "$IDPF/accessible_epub_3.epub"
fetch idpf_cc-shared-culture.epub  "$IDPF/cc-shared-culture.epub"
fetch idpf_childrens-lit.epub      "$IDPF/childrens-literature.epub"
fetch idpf_kusamakura-vertical.epub "$IDPF/kusamakura-japanese-vertical-writing.epub"
fetch idpf_page-blanche.epub       "$IDPF/page-blanche.epub"
fetch idpf_israelsailing-rtl.epub  "$IDPF/israelsailing.epub"
fetch idpf_svg-in-spine.epub       "$IDPF/svg-in-spine.epub"

echo
echo "corpus: $(ls -1 *.epub 2>/dev/null | wc -l) files"
