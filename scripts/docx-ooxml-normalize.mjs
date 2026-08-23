#!/usr/bin/env node
/**
 * docx-ooxml-normalize.mjs — GDrive / interop OOXML normalization for .docx (Node-only).
 *
 * Rounds float twips and fixes common Google Docs export patterns so strict
 * OpenXmlValidator passes while preserving Word/GDrive editability.
 *
 * Usage:
 *   node docx-ooxml-normalize.mjs [--in-place] [--detect-only] DOCX
 */
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));

function listWordXmlParts(tmpDir) {
  const wordDir = path.join(tmpDir, 'word');
  if (!fs.existsSync(wordDir)) return [];
  return fs
    .readdirSync(wordDir)
    .filter((name) => name.endsWith('.xml'))
    .map((name) => `word/${name}`)
    .sort();
}

const FLOAT_MEASURE_ATTRS = ['w', 'line', 'top', 'bottom', 'left', 'right', 'before', 'after', 'h', 'space', 'sz'];
const ON_OFF_TAGS = new Set([
  'tblHeader',
  'cantSplit',
  'hidden',
  'b',
  'i',
  'caps',
  'strike',
  'dstrike',
  'outline',
  'shadow',
  'emboss',
  'imprint',
  'noProof',
  'snapToGrid',
  'wordWrap',
  'overflowPunct',
  'topLinePunct',
  'autoSpaceDE',
  'autoSpaceDN',
  'bidi',
  'adjustRightInd',
  'suppressOverlap',
  'suppressAutoHyphens',
  'suppressLineNumbers',
  'contextualSpacing',
]);

function usage() {
  console.error(`Usage:
  docx-ooxml-normalize.mjs [--in-place] [--detect-only] DOCX

Options:
  --in-place     Rewrite DOCX in place (creates timestamped .bak beside file first)
  --detect-only  Print JSON { needsNormalize, reason } and exit 0 without changes`);
  process.exit(2);
}

function parseArgs(argv) {
  const flags = { inPlace: false, detectOnly: false };
  const positional = [];
  for (const arg of argv) {
    if (arg === '--in-place') flags.inPlace = true;
    else if (arg === '--detect-only') flags.detectOnly = true;
    else if (arg.startsWith('--')) {
      console.error(`docx-ooxml-normalize: unknown option ${arg}`);
      process.exit(2);
    } else positional.push(arg);
  }
  return { flags, positional };
}

function detectInteropPatterns(xml) {
  if (/\bw:(?:w|line|top|bottom|left|right|before|after|h|space|sz)="[0-9]+\.[0-9]+"/.test(xml)) {
    return 'float-twips-attributes';
  }
  if (/\bw:val="[0-9]+\.[0-9]+"/.test(xml)) {
    return 'float-val-attributes';
  }
  if (/<w:tblHeader\b[^>]*\bw:val="[01]"/.test(xml)) {
    return 'tblHeader-zero-one-enums';
  }
  return null;
}

function roundFloatAttr(xml, attr, changes) {
  const re = new RegExp(`(\\bw:${attr}=")([0-9]+\\.[0-9]+)(")`, 'g');
  return xml.replace(re, (match, pre, num, post) => {
    changes.count += 1;
    return `${pre}${Math.round(parseFloat(num))}${post}`;
  });
}

function fixOnOffVal(xml, tag, changes) {
  let out = xml;
  for (const [from, to] of [['0', 'off'], ['1', 'on']]) {
    const re = new RegExp(`(<w:${tag}\\b[^>]*\\bw:val=")${from}(")`, 'g');
    out = out.replace(re, (match, pre, post) => {
      changes.count += 1;
      return `${pre}${to}${post}`;
    });
  }
  return out;
}

function roundFloatVal(xml, changes) {
  return xml.replace(/(\bw:val=")([0-9]+\.[0-9]+)(")/g, (match, pre, num, post) => {
    changes.count += 1;
    return `${pre}${Math.round(parseFloat(num))}${post}`;
  });
}

function dedupeBookmarkIds(xml, changes) {
  const idRe = /\bw:id="(\d+)"/g;
  const seen = new Map();
  let maxId = 0;
  for (const match of xml.matchAll(idRe)) {
    const id = Number.parseInt(match[1], 10);
    if (!Number.isNaN(id)) maxId = Math.max(maxId, id);
  }
  let nextId = maxId + 1;
  return xml.replace(idRe, (match, idStr) => {
    const id = idStr;
    if (!seen.has(id)) {
      seen.set(id, 1);
      return match;
    }
    changes.count += 1;
    const replacement = String(nextId);
    nextId += 1;
    return `w:id="${replacement}"`;
  });
}

function normalizeXml(xml) {
  const changes = { count: 0 };
  let out = xml;
  for (const attr of FLOAT_MEASURE_ATTRS) {
    out = roundFloatAttr(out, attr, changes);
  }
  out = roundFloatVal(out, changes);
  for (const tag of ON_OFF_TAGS) {
    out = fixOnOffVal(out, tag, changes);
  }
  out = dedupeBookmarkIds(out, changes);
  return { xml: out, changes: changes.count };
}

function zipDir(srcDir, destDocx) {
  execFileSync('zip', ['-qr', destDocx, '.'], { cwd: srcDir, stdio: 'pipe' });
}

function unzipDocx(docxPath, destDir) {
  execFileSync('unzip', ['-qq', '-o', docxPath, '-d', destDir], { stdio: 'pipe' });
}

function normalizeDocx(docxPath, { inPlace }) {
  const resolved = path.resolve(docxPath);
  if (!fs.existsSync(resolved)) {
    console.error(`docx-ooxml-normalize: file not found: ${resolved}`);
    process.exit(1);
  }

  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'docx-norm-'));
  try {
    unzipDocx(resolved, tmp);
    const parts = listWordXmlParts(tmp);
    let totalChanges = 0;
    let reasons = new Set();

    for (const rel of parts) {
      const partPath = path.join(tmp, rel);
      if (!fs.existsSync(partPath)) continue;
      const src = fs.readFileSync(partPath, 'utf8');
      const reason = detectInteropPatterns(src);
      if (reason) reasons.add(reason);
      const { xml, changes } = normalizeXml(src);
      if (changes > 0) {
        fs.writeFileSync(partPath, xml);
        totalChanges += changes;
      }
    }

    if (totalChanges === 0) {
      return {
        docxPath: resolved,
        changed: false,
        changes: 0,
        reasons: [...reasons],
      };
    }

    const outDocx = inPlace ? resolved : path.join(tmp, 'normalized.docx');
    if (inPlace) {
      const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\..+/, '');
      fs.copyFileSync(resolved, `${resolved}.bak-${stamp}`);
    }
    zipDir(tmp, outDocx);
    if (!inPlace) {
      fs.copyFileSync(outDocx, resolved);
    }

    return {
      docxPath: resolved,
      changed: true,
      changes: totalChanges,
      reasons: [...reasons],
    };
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

function detectDocx(docxPath) {
  const resolved = path.resolve(docxPath);
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'docx-detect-'));
  try {
    unzipDocx(resolved, tmp);
    const parts = listWordXmlParts(tmp);
    for (const rel of parts) {
      const partPath = path.join(tmp, rel);
      if (!fs.existsSync(partPath)) continue;
      const reason = detectInteropPatterns(fs.readFileSync(partPath, 'utf8'));
      if (reason) {
        return { needsNormalize: true, reason };
      }
    }
    return { needsNormalize: false, reason: null };
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

function main() {
  const { flags, positional } = parseArgs(process.argv.slice(2));
  if (positional.length !== 1) usage();
  const docxPath = positional[0];

  if (flags.detectOnly) {
    console.log(JSON.stringify(detectDocx(docxPath)));
    return;
  }

  const result = normalizeDocx(docxPath, { inPlace: flags.inPlace });
  console.log(JSON.stringify(result));
}

main();
