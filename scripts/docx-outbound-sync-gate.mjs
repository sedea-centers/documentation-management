#!/usr/bin/env node
/**
 * docx-outbound-sync-gate.mjs — fail closed before outbound rclone bisync/sync
 * when pending OOXML markup exists.
 *
 * Usage:
 *   node docx-outbound-sync-gate.mjs [--markup-pending true|false] DOCX
 *   node docx-outbound-sync-gate.mjs --self-test
 *
 * Exit 0: outbound sync may proceed
 * Exit 1: sync blocked (pending markup)
 * Exit 2: usage / prerequisite failure
 */
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const markupScript = path.join(scriptDir, 'docx-markup.mjs');

function usage() {
  console.error(`Usage:
  docx-outbound-sync-gate.mjs [--markup-pending true|false] DOCX
  docx-outbound-sync-gate.mjs --self-test

Exit 0 when outbound sync may proceed; exit 1 when pending markup blocks sync.`);
  process.exit(2);
}

function parseArgs(argv) {
  const flags = {};
  const positional = [];
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--markup-pending') {
      flags.markupPending = argv[i + 1];
      i += 1;
    } else if (arg === '--self-test') {
      flags.selfTest = true;
    } else if (arg.startsWith('-')) {
      console.error(`docx-outbound-sync-gate: unknown flag ${arg}`);
      usage();
    } else {
      positional.push(arg);
    }
  }
  return { flags, positional };
}

function listPendingFromFile(docxPath) {
  if (!fs.existsSync(markupScript)) {
    console.error(`docx-outbound-sync-gate: missing ${markupScript}`);
    process.exit(2);
  }
  const stdout = execFileSync(process.execPath, [markupScript, 'list-pending', docxPath], {
    encoding: 'utf8',
  });
  return JSON.parse(stdout.trim());
}

function gate(docxPath, markupPendingFlag) {
  if (!fs.existsSync(docxPath)) {
    console.error(`docx-outbound-sync-gate: file not found: ${docxPath}`);
    process.exit(2);
  }
  if (!docxPath.toLowerCase().endsWith('.docx')) {
    return { allowed: true, reason: 'non-docx path — gate not applicable' };
  }

  if (markupPendingFlag === 'true') {
    return {
      allowed: false,
      reason: 'markupPending: true from upstream skill output — outbound sync blocked until pending markup clears',
    };
  }
  if (markupPendingFlag === 'false') {
    return { allowed: true, reason: 'markupPending: false from upstream skill output' };
  }

  const report = listPendingFromFile(docxPath);
  if (report.pending) {
    return {
      allowed: false,
      reason: `list-pending reports pending markup (ins=${report.insCount}, del=${report.delCount}, red=${report.redRunCount}) — outbound sync blocked`,
      report,
    };
  }
  return { allowed: true, reason: 'list-pending reports no pending markup', report };
}

function createMinimalDocx(tmpDir) {
  const docx = path.join(tmpDir, 'minimal.docx');
  const root = path.join(tmpDir, 'pkg');
  fs.mkdirSync(path.join(root, '_rels'), { recursive: true });
  fs.mkdirSync(path.join(root, 'word', '_rels'), { recursive: true });
  fs.writeFileSync(
    path.join(root, '[Content_Types].xml'),
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>`,
  );
  fs.writeFileSync(
    path.join(root, '_rels', '.rels'),
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>`,
  );
  fs.writeFileSync(
    path.join(root, 'word', 'document.xml'),
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body><w:p><w:r><w:t>gate</w:t></w:r></w:p></w:body>
</w:document>`,
  );
  fs.writeFileSync(
    path.join(root, 'word', '_rels', 'document.xml.rels'),
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>`,
  );
  execFileSync('zip', ['-qr', docx, '[Content_Types].xml', '_rels', 'word'], { cwd: root });
  return docx;
}

function selfTest() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'docx-outbound-sync-gate-'));
  try {
    const clean = createMinimalDocx(tmp);
    const pending = path.join(tmp, 'pending.docx');
    fs.copyFileSync(clean, pending);
    execFileSync(process.execPath, [markupScript, 'mark-insert', pending, '--text', ' pending']);

    const allowClean = gate(clean, undefined);
    if (!allowClean.allowed) {
      throw new Error(`expected clean docx to pass; got ${allowClean.reason}`);
    }

    const blockPending = gate(pending, undefined);
    if (blockPending.allowed) {
      throw new Error('expected pending docx to block without markupPending flag');
    }

    const blockTrue = gate(pending, 'true');
    if (blockTrue.allowed) {
      throw new Error('expected markupPending true to block');
    }

    const allowFalse = gate(pending, 'false');
    if (!allowFalse.allowed) {
      throw new Error('expected markupPending false to allow even when file pending');
    }

    console.log('docx-outbound-sync-gate: self-test passed');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

function main() {
  const { flags, positional } = parseArgs(process.argv.slice(2));
  if (flags.selfTest) {
    selfTest();
    return;
  }
  const docxPath = positional[0];
  if (!docxPath) {
    usage();
  }
  const resolved = path.resolve(docxPath);
  const result = gate(resolved, flags.markupPending);
  if (!result.allowed) {
    console.error(`docx-outbound-sync-gate: ${result.reason}`);
    process.exit(1);
  }
}

const entryPath = process.argv[1] ? path.resolve(process.argv[1]) : '';
if (entryPath && entryPath === fileURLToPath(import.meta.url)) {
  main();
}
