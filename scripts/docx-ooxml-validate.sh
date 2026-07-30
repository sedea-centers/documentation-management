#!/usr/bin/env bash
# Validate .docx OOXML package hygiene + schema (Node-first; no Python).
# Usage: docx-ooxml-validate.sh [--self-test] ABS_PATH.docx
set -euo pipefail

OOXML_VALIDATOR_PKG="@xarsh/ooxml-validator@0.2.0"

usage() {
  echo "Usage: docx-ooxml-validate.sh [--self-test] ABS_PATH.docx" >&2
  exit 2
}

require_node() {
  if ! command -v node >/dev/null 2>&1 || ! command -v npx >/dev/null 2>&1; then
    echo "docx-ooxml-validate: node and npx are required on PATH." >&2
    echo "Start Required Tools Installation (install required tools) on documentation-management." >&2
    exit 2
  fi
}

hygiene_check() {
  local docx="$1"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  if ! unzip -qq -o "$docx" -d "$tmp" >/dev/null 2>&1; then
    echo "docx-ooxml-validate: not a readable ZIP/docx package: $docx" >&2
    return 1
  fi

  local ct="$tmp/[Content_Types].xml"
  if [[ -f "$ct" ]] && grep -qE 'xmlns:ns[0-9]+=|<ns[0-9]+:' "$ct"; then
    echo "docx-ooxml-validate: prefixed default xmlns on [Content_Types].xml (Word-hostile)." >&2
    return 1
  fi

  local rel
  while IFS= read -r -d '' rel; do
    if grep -qE 'xmlns:ns[0-9]+=|<ns[0-9]+:' "$rel"; then
      echo "docx-ooxml-validate: prefixed default xmlns on ${rel#$tmp/} (Word-hostile)." >&2
      return 1
    fi
  done < <(find "$tmp" -name '*.rels' -print0)
}

run_ooxml_validator() {
  local docx="$1"
  local json ok
  json="$(npx --yes "$OOXML_VALIDATOR_PKG" "$docx")"
  ok="$(printf '%s' "$json" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{try{const j=JSON.parse(s);process.stdout.write(j.ok===true?"true":"false")}catch{process.stdout.write("false")}})')"
  if [[ "$ok" != "true" ]]; then
    echo "docx-ooxml-validate: OOXML validator reported errors for $docx" >&2
    printf '%s\n' "$json" >&2
    return 1
  fi
}

self_test() {
  require_node
  local tmp docx
  tmp="$(mktemp -d)"
  docx="$tmp/minimal.docx"
  # Minimal OOXML package Word accepts (empty document).
  mkdir -p "$tmp/_rels" "$tmp/word/_rels"
  cat >"$tmp/[Content_Types].xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
EOF
  cat >"$tmp/_rels/.rels" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
EOF
  cat >"$tmp/word/document.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body><w:p><w:r><w:t>validate</w:t></w:r></w:p></w:body>
</w:document>
EOF
  cat >"$tmp/word/_rels/document.xml.rels" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>
EOF
  (cd "$tmp" && zip -qr "$docx" '[Content_Types].xml' _rels word)
  hygiene_check "$docx"
  run_ooxml_validator "$docx"
  rm -rf "$tmp"
  echo "docx-ooxml-validate: self-test passed"
}

main() {
  if [[ $# -lt 1 ]]; then
    usage
  fi
  if [[ "$1" == "--self-test" ]]; then
    self_test
    exit 0
  fi
  local docx="$1"
  if [[ ! -f "$docx" ]]; then
    echo "docx-ooxml-validate: file not found: $docx" >&2
    exit 1
  fi
  case "$docx" in
    *.docx) ;;
    *)
      echo "docx-ooxml-validate: expected a .docx file: $docx" >&2
      exit 1
      ;;
  esac
  require_node
  hygiene_check "$docx"
  run_ooxml_validator "$docx"
  echo "docx-ooxml-validate: passed $docx"
}

main "$@"
