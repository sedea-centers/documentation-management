#!/usr/bin/env bash
# Validate .docx OOXML package hygiene + schema (Node-first; no Python).
# Usage: docx-ooxml-validate.sh [--self-test] [--normalize|--no-normalize] [--verbose] ABS_PATH.docx
#
# --normalize     Apply GDrive/interop normalization before schema validation.
# --no-normalize  Skip normalization (strict validator only).
# Default: auto-normalize when float-twips interop patterns are detected.
#
# Windows: run under Git bash. --self-test needs `zip` on that bash PATH
# (stock Git for Windows may ship unzip without zip; missing zip → exit 127).
set -euo pipefail

OOXML_VALIDATOR_PKG="@xarsh/ooxml-validator@0.2.0"

usage() {
  echo "Usage: docx-ooxml-validate.sh [--self-test] [--normalize|--no-normalize] [--verbose] ABS_PATH.docx" >&2
  exit 2
}

require_node() {
  if ! command -v node >/dev/null 2>&1 || ! command -v npx >/dev/null 2>&1; then
    echo "docx-ooxml-validate: node and npx are required on PATH." >&2
    echo "Start Required Tools Installation (install required tools) on documentation-management." >&2
    exit 2
  fi
}

script_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

hygiene_check() {
  local docx="$1"
  local tmp
  tmp="$(mktemp -d)"

  if ! unzip -qq -o "$docx" -d "$tmp" >/dev/null 2>&1; then
    rm -rf "$tmp"
    echo "docx-ooxml-validate: not a readable ZIP/docx package: $docx" >&2
    return 1
  fi

  local ct="$tmp/[Content_Types].xml"
  if [[ -f "$ct" ]] && grep -qE 'xmlns:ns[0-9]+=|<ns[0-9]+:' "$ct"; then
    rm -rf "$tmp"
    echo "docx-ooxml-validate: prefixed default xmlns on [Content_Types].xml (Word-hostile)." >&2
    return 1
  fi

  local rel
  while IFS= read -r -d '' rel; do
    if grep -qE 'xmlns:ns[0-9]+=|<ns[0-9]+:' "$rel"; then
      rm -rf "$tmp"
      echo "docx-ooxml-validate: prefixed default xmlns on ${rel#$tmp/} (Word-hostile)." >&2
      return 1
    fi
  done < <(find "$tmp" -name '*.rels' -print0)

  rm -rf "$tmp"
}

maybe_normalize() {
  local docx="$1"
  local mode="$2"
  local normalize_script="$3"
  local detect_json needs reason

  if [[ "$mode" == "never" ]]; then
    return 0
  fi

  if [[ ! -f "$normalize_script" ]]; then
    echo "docx-ooxml-validate: missing docx-ooxml-normalize.mjs beside validator" >&2
    return 1
  fi

  if [[ "$mode" == "always" ]]; then
    echo "docx-ooxml-validate: applying GDrive/interop normalize (--normalize) for $docx" >&2
    node "$normalize_script" --in-place "$docx" >&2 || return 1
    return 0
  fi

  detect_json="$(node "$normalize_script" --detect-only "$docx")"
  needs="$(printf '%s' "$detect_json" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{try{const j=JSON.parse(s);process.stdout.write(j.needsNormalize===true?"yes":"no")}catch{process.stdout.write("no")}})')"
  if [[ "$needs" != "yes" ]]; then
    return 0
  fi
  reason="$(printf '%s' "$detect_json" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{try{const j=JSON.parse(s);process.stdout.write(j.reason||"interop")}catch{process.stdout.write("interop")}})')"
  echo "docx-ooxml-validate: auto-normalize ($reason) for $docx" >&2
  node "$normalize_script" --in-place "$docx" >&2 || return 1
}

emit_error_summary() {
  local json_file="$1"
  local verbose="$2"
  node - "$json_file" "$verbose" <<'NODE'
const fs = require('fs');
const jsonFile = process.argv[2];
const verbose = process.argv[3] === '1';
let j;
try {
  j = JSON.parse(fs.readFileSync(jsonFile, 'utf8'));
} catch {
  console.error('docx-ooxml-validate: validator returned non-JSON output');
  process.exit(0);
}
const errs = j.errors || [];
console.error(`docx-ooxml-validate: ${errs.length} validation error(s)`);
const byType = {};
const byId = {};
for (const e of errs) {
  byType[e.errorType || 'unknown'] = (byType[e.errorType || 'unknown'] || 0) + 1;
  byId[e.id || 'unknown'] = (byId[e.id || 'unknown'] || 0) + 1;
}
for (const [k, v] of Object.entries(byType).sort((a, b) => b[1] - a[1])) {
  console.error(`  ${k}: ${v}`);
}
for (const [id, count] of Object.entries(byId).sort((a, b) => b[1] - a[1]).slice(0, 5)) {
  console.error(`  ${id}: ${count}`);
}
if (verbose) {
  console.error('docx-ooxml-validate: full validator JSON follows');
  console.error(JSON.stringify(j, null, 2));
} else {
  console.error('docx-ooxml-validate: re-run with --verbose for full JSON report');
}
NODE
}

run_ooxml_validator() {
  local docx="$1"
  local verbose="$2"
  local json_file ok npx_exit=0

  json_file="$(mktemp "${TMPDIR:-/tmp}/docx-validate.XXXXXX")"
  set +e
  npx --yes "$OOXML_VALIDATOR_PKG" "$docx" >"$json_file" 2>/dev/null
  npx_exit=$?
  set -e

  if [[ ! -s "$json_file" ]]; then
    rm -f "$json_file"
    echo "docx-ooxml-validate: validator produced no output for $docx (npx exit $npx_exit)" >&2
    return 1
  fi

  ok="$(node -e "const j=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));process.stdout.write(j.ok===true?'true':'false');" "$json_file")"
  if [[ "$ok" != "true" ]]; then
    echo "docx-ooxml-validate: OOXML validator reported errors for $docx" >&2
    emit_error_summary "$json_file" "$verbose"
    rm -f "$json_file"
    return 1
  fi
  rm -f "$json_file"
}

self_test() {
  require_node
  local tmp docx dir markup normalize
  tmp="$(mktemp -d)"
  docx="$tmp/minimal.docx"
  dir="$(script_dir)"
  markup="$dir/docx-markup.mjs"
  normalize="$dir/docx-ooxml-normalize.mjs"
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
  run_ooxml_validator "$docx" 0

  if [[ ! -f "$markup" ]]; then
    echo "docx-ooxml-validate: missing docx-markup.mjs beside validator" >&2
    return 1
  fi
  if [[ ! -f "$normalize" ]]; then
    echo "docx-ooxml-validate: missing docx-ooxml-normalize.mjs beside validator" >&2
    return 1
  fi

  local track_docx="$tmp/track-change.docx"
  local red_docx="$tmp/red-run.docx"
  cp "$docx" "$track_docx"
  cp "$docx" "$red_docx"

  node "$markup" mark-insert "$track_docx" --text " pending insert"
  hygiene_check "$track_docx"
  run_ooxml_validator "$track_docx" 0

  node "$markup" mark-delete "$track_docx" --text "validate"
  hygiene_check "$track_docx"
  run_ooxml_validator "$track_docx" 0

  node "$markup" mark-red "$red_docx" --text "validate"
  hygiene_check "$red_docx"
  run_ooxml_validator "$red_docx" 0

  node "$markup" list-pending "$track_docx" >/dev/null
  node "$markup" accept-all "$track_docx"
  hygiene_check "$track_docx"
  run_ooxml_validator "$track_docx" 0

  # GDrive/interop fixture: float twips trigger detect + auto-normalize path.
  local interop_docx="$tmp/interop-float.docx"
  mkdir -p "$tmp/interop/_rels" "$tmp/interop/word/_rels"
  cat >"$tmp/interop/[Content_Types].xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
EOF
  cat >"$tmp/interop/_rels/.rels" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
EOF
  cat >"$tmp/interop/word/document.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:pPr><w:spacing w:before="12.5" w:after="6.75"/></w:pPr>
      <w:r><w:t>interop</w:t></w:r>
    </w:p>
  </w:body>
</w:document>
EOF
  cat >"$tmp/interop/word/_rels/document.xml.rels" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>
EOF
  (cd "$tmp/interop" && zip -qr "$interop_docx" '[Content_Types].xml' _rels word)

  local detect_json needs
  detect_json="$(node "$normalize" --detect-only "$interop_docx")"
  needs="$(printf '%s' "$detect_json" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{try{const j=JSON.parse(s);process.stdout.write(j.needsNormalize===true?"yes":"no")}catch{process.stdout.write("no")}})')"
  if [[ "$needs" != "yes" ]]; then
    echo "docx-ooxml-validate: self-test interop detect expected needsNormalize" >&2
    return 1
  fi

  local interop_norm="$tmp/interop-normalized.docx"
  cp "$interop_docx" "$interop_norm"
  hygiene_check "$interop_norm"
  maybe_normalize "$interop_norm" "auto" "$normalize"
  run_ooxml_validator "$interop_norm" 0

  rm -rf "$tmp"
  echo "docx-ooxml-validate: self-test passed"
}

main() {
  local normalize_mode="auto"
  local verbose=0
  local docx=""
  local arg dir normalize_script

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --self-test)
        self_test
        exit 0
        ;;
      --normalize)
        normalize_mode="always"
        shift
        ;;
      --no-normalize)
        normalize_mode="never"
        shift
        ;;
      --verbose)
        verbose=1
        shift
        ;;
      -*)
        usage
        ;;
      *)
        docx="$1"
        shift
        ;;
    esac
  done

  if [[ -z "$docx" ]]; then
    usage
  fi
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
  dir="$(script_dir)"
  normalize_script="$dir/docx-ooxml-normalize.mjs"
  hygiene_check "$docx"
  maybe_normalize "$docx" "$normalize_mode" "$normalize_script"
  run_ooxml_validator "$docx" "$verbose"
  echo "docx-ooxml-validate: passed $docx"
}

main "$@"
