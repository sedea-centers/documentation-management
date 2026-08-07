#!/usr/bin/env node
/**
 * docx-markup.mjs — pending OOXML markup for .docx authoring (Node-only).
 *
 * Usage:
 *   node docx-markup.mjs mark-insert DOCX --text "..."
 *   node docx-markup.mjs mark-delete DOCX --text "..."
 *   node docx-markup.mjs mark-red DOCX --text "..."
 *   node docx-markup.mjs list-pending DOCX
 *   node docx-markup.mjs accept-all DOCX
 */
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DEFAULT_AUTHOR = 'Sedea Author Agent';
const W_NS = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const RED_COLOR = 'FF0000';

function usage() {
  console.error(`Usage:
  docx-markup.mjs mark-insert DOCX --text "..."
  docx-markup.mjs mark-delete DOCX --text "..."
  docx-markup.mjs mark-red DOCX --text "..."
  docx-markup.mjs list-pending DOCX
  docx-markup.mjs accept-all DOCX

Options:
  --text <string>   Target text (mark-insert | mark-delete | mark-red)
  --author <name>   w:author for track changes (default: ${DEFAULT_AUTHOR})`);
  process.exit(2);
}

function parseArgs(argv) {
  const positional = [];
  const flags = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--text' || arg === '--author') {
      const value = argv[i + 1];
      if (value == null || value.startsWith('--')) {
        console.error(`docx-markup: missing value for ${arg}`);
        process.exit(2);
      }
      flags[arg.slice(2)] = value;
      i += 1;
    } else if (arg.startsWith('--')) {
      console.error(`docx-markup: unknown option ${arg}`);
      process.exit(2);
    } else {
      positional.push(arg);
    }
  }
  return { positional, flags };
}

function escapeXml(text) {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function escapeRegex(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function isoDate() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
}

class DocxPackage {
  constructor(docxPath) {
    this.docxPath = path.resolve(docxPath);
    if (!fs.existsSync(this.docxPath)) {
      console.error(`docx-markup: file not found: ${this.docxPath}`);
      process.exit(1);
    }
    if (!this.docxPath.endsWith('.docx')) {
      console.error(`docx-markup: expected a .docx file: ${this.docxPath}`);
      process.exit(1);
    }
    this.tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'docx-markup-'));
  }

  extract() {
    execFileSync('unzip', ['-qq', '-o', this.docxPath, '-d', this.tmpDir], {
      stdio: ['ignore', 'ignore', 'pipe'],
    });
  }

  repack() {
    const entries = ['[Content_Types].xml', '_rels', 'word'];
    execFileSync('zip', ['-qr', this.docxPath, ...entries], {
      cwd: this.tmpDir,
      stdio: ['ignore', 'ignore', 'pipe'],
    });
  }

  readDocumentXml() {
    const docPath = path.join(this.tmpDir, 'word', 'document.xml');
    if (!fs.existsSync(docPath)) {
      console.error('docx-markup: missing word/document.xml');
      process.exit(1);
    }
    return fs.readFileSync(docPath, 'utf8');
  }

  writeDocumentXml(xml) {
    fs.writeFileSync(path.join(this.tmpDir, 'word', 'document.xml'), xml, 'utf8');
  }

  cleanup() {
    fs.rmSync(this.tmpDir, { recursive: true, force: true });
  }

  mutate(mutator) {
    this.extract();
    const xml = this.readDocumentXml();
    const next = mutator(xml);
    this.writeDocumentXml(next);
    this.ensureTrackRevisions();
    this.repack();
    this.cleanup();
  }

  ensureTrackRevisions() {
    const settingsPath = path.join(this.tmpDir, 'word', 'settings.xml');
    const settingsRelsPath = path.join(this.tmpDir, 'word', '_rels', 'document.xml.rels');
    const contentTypesPath = path.join(this.tmpDir, '[Content_Types].xml');

    if (fs.existsSync(settingsPath)) {
      let settings = fs.readFileSync(settingsPath, 'utf8');
      if (!settings.includes('w:trackRevisions')) {
        settings = settings.replace(
          /<\/w:settings>\s*$/,
          '  <w:trackRevisions/>\n</w:settings>',
        );
        fs.writeFileSync(settingsPath, settings, 'utf8');
      }
      return;
    }

    const settingsXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:settings xmlns:w="${W_NS}">
  <w:trackRevisions/>
</w:settings>`;
    fs.writeFileSync(settingsPath, settingsXml, 'utf8');

    let rels = fs.readFileSync(settingsRelsPath, 'utf8');
    if (!rels.includes('settings.xml')) {
      const ids = [...rels.matchAll(/Id="rId(\d+)"/g)].map((m) => Number(m[1]));
      const nextId = (ids.length ? Math.max(...ids) : 0) + 1;
      rels = rels.replace(
        /<\/Relationships>\s*$/,
        `  <Relationship Id="rId${nextId}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>\n</Relationships>`,
      );
      fs.writeFileSync(settingsRelsPath, rels, 'utf8');
    }

    let contentTypes = fs.readFileSync(contentTypesPath, 'utf8');
    if (!contentTypes.includes('/word/settings.xml')) {
      contentTypes = contentTypes.replace(
        /<\/Types>\s*$/,
        '  <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>\n</Types>',
      );
      fs.writeFileSync(contentTypesPath, contentTypes, 'utf8');
    }
  }
}

function nextRevisionId(xml) {
  const ids = [...xml.matchAll(/\bw:id="(\d+)"/g)].map((m) => Number(m[1]));
  return (ids.length ? Math.max(...ids) : 0) + 1;
}

function needsPreserveSpace(text) {
  return /^\s|\s$|\s{2,}/.test(text);
}

function textElement(tag, text) {
  const preserve = needsPreserveSpace(text) ? ' xml:space="preserve"' : '';
  return `<${tag}${preserve}>${escapeXml(text)}</${tag}>`;
}

function markInsert(xml, text, author) {
  const id = nextRevisionId(xml);
  const date = isoDate();
  const t = textElement('w:t', text);
  const block =
    `<w:ins w:id="${id}" w:author="${escapeXml(author)}" w:date="${date}">` +
    `<w:r>${t}</w:r></w:ins>`;
  const paragraph = `<w:p>${block}</w:p>`;

  if (xml.includes('<w:sectPr')) {
    return xml.replace(/<w:sectPr/, `${paragraph}<w:sectPr`);
  }
  return xml.replace(/<\/w:body>\s*<\/w:document>/, `${paragraph}</w:body></w:document>`);
}

function markDelete(xml, text, author) {
  const pattern = new RegExp(
    `<w:r>(\\s*(?:<w:rPr>[\\s\\S]*?</w:rPr>\\s*)?)<w:t(?:\\s+xml:space="preserve")?>` +
      `${escapeRegex(text)}</w:t>\\s*</w:r>`,
  );
  if (!pattern.test(xml)) {
    console.error(`docx-markup: mark-delete: text not found in document: ${text}`);
    process.exit(1);
  }
  const id = nextRevisionId(xml);
  const date = isoDate();
  return xml.replace(
    pattern,
    (_match, rPr) => {
      const delText = textElement('w:delText', text);
      return (
        `<w:del w:id="${id}" w:author="${escapeXml(author)}" w:date="${date}">` +
        `<w:r>${rPr ?? ''}${delText}</w:r></w:del>`
      );
    },
  );
}

function markRed(xml, text) {
  const pattern = new RegExp(
    `<w:r>(\\s*(?:<w:rPr>[\\s\\S]*?</w:rPr>\\s*)?)<w:t(?:\\s+xml:space="preserve")?>` +
      `${escapeRegex(text)}</w:t>\\s*</w:r>`,
  );
  if (!pattern.test(xml)) {
    console.error(`docx-markup: mark-red: text not found in document: ${text}`);
    process.exit(1);
  }
  return xml.replace(pattern, (match, rPr) => {
    if (rPr) {
      if (rPr.includes('w:color')) {
        return match.replace(/w:val="[^"]+"/, `w:val="${RED_COLOR}"`);
      }
      const updatedRPr = rPr.replace(/<\/w:rPr>/, `<w:color w:val="${RED_COLOR}"/></w:rPr>`);
      return match.replace(rPr, updatedRPr);
    }
    const colorPr = `<w:rPr><w:color w:val="${RED_COLOR}"/></w:rPr>`;
    const t = textElement('w:t', text);
    return `<w:r>${colorPr}${t}</w:r>`;
  });
}

function countMatches(xml, pattern) {
  return [...xml.matchAll(pattern)].length;
}

function listPending(xml) {
  const insCount = countMatches(xml, /<w:ins\b/g);
  const delCount = countMatches(xml, /<w:del\b/g);
  const redRunCount = countMatches(xml, /<w:color\s+w:val="FF0000"\s*\/>/g);
  const pending = insCount + delCount + redRunCount > 0;
  return { insCount, delCount, redRunCount, pending };
}

function flattenIns(xml) {
  let result = xml;
  const pattern = /<w:ins\b[^>]*>([\s\S]*?)<\/w:ins>/g;
  for (let i = 0; i < 50; i += 1) {
    const next = result.replace(pattern, '$1');
    if (next === result) break;
    result = next;
  }
  return result;
}

function removeDel(xml) {
  return xml.replace(/<w:del\b[^>]*>[\s\S]*?<\/w:del>/g, '');
}

function stripRedColor(xml) {
  let result = xml;
  result = result.replace(
    /<w:rPr>\s*<w:color\s+w:val="FF0000"\s*\/>\s*<\/w:rPr>/g,
    '',
  );
  result = result.replace(
    /(<w:rPr>[\s\S]*?)<w:color\s+w:val="FF0000"\s*\/>([\s\S]*?<\/w:rPr>)/g,
    '$1$2',
  );
  result = result.replace(/<w:rPr>\s*<\/w:rPr>/g, '');
  return result;
}

function acceptAll(xml) {
  return stripRedColor(removeDel(flattenIns(xml)));
}

export {
  acceptAll,
  listPending,
  markDelete,
  markInsert,
  markRed,
};

function main() {
  const { positional, flags } = parseArgs(process.argv.slice(2));
  if (positional.length < 2) usage();

  const [command, docxPath] = positional;
  const author = flags.author ?? DEFAULT_AUTHOR;
  const text = flags.text;

  const pkg = new DocxPackage(docxPath);

  switch (command) {
    case 'mark-insert': {
      if (!text) {
        console.error('docx-markup: mark-insert requires --text');
        process.exit(2);
      }
      pkg.mutate((xml) => markInsert(xml, text, author));
      break;
    }
    case 'mark-delete': {
      if (!text) {
        console.error('docx-markup: mark-delete requires --text');
        process.exit(2);
      }
      pkg.mutate((xml) => markDelete(xml, text, author));
      break;
    }
    case 'mark-red': {
      if (!text) {
        console.error('docx-markup: mark-red requires --text');
        process.exit(2);
      }
      pkg.mutate((xml) => markRed(xml, text));
      break;
    }
    case 'list-pending': {
      pkg.extract();
      const result = listPending(pkg.readDocumentXml());
      pkg.cleanup();
      console.log(JSON.stringify(result));
      break;
    }
    case 'accept-all': {
      pkg.mutate((xml) => acceptAll(xml));
      break;
    }
    default:
      console.error(`docx-markup: unknown command ${command}`);
      usage();
  }
}

const entryPath = process.argv[1] ? path.resolve(process.argv[1]) : '';
if (entryPath && entryPath === fileURLToPath(import.meta.url)) {
  main();
}
