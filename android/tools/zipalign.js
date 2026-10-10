/*
 *  zipalign.js  —  بسته‌بندی و هم‌ترازسازی APK
 *
 *  کارهایی که انجام می‌دهد:
 *    1) فایل‌های اضافی (مثل classes.dex) را به APK اضافه می‌کند
 *    2) همهٔ ورودی‌ها را طوری می‌چیند که داده‌شان روی مرز ۴ بایتی باشد (zipalign)
 *
 *  استفاده:
 *    node zipalign.js <in.apk> <out.apk> [name=path ...]
 */
const fs = require('fs');
const zlib = require('zlib');

const ALIGN = 4;

/* ---------- CRC32 ---------- */
const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();

function crc32(buf) {
  let crc = -1;
  for (let i = 0; i < buf.length; i++) crc = (crc >>> 8) ^ CRC_TABLE[(crc ^ buf[i]) & 0xff];
  return (crc ^ -1) >>> 0;
}

/* ---------- خواندن ورودی‌های موجود APK ---------- */
function readEntries(buf) {
  let eocd = -1;
  const minPos = Math.max(0, buf.length - 65557);
  for (let i = buf.length - 22; i >= minPos; i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error('EOCD پیدا نشد — فایل zip معتبر نیست');

  const total = buf.readUInt16LE(eocd + 10);
  let p = buf.readUInt32LE(eocd + 16);

  const entries = [];
  for (let i = 0; i < total; i++) {
    if (buf.readUInt32LE(p) !== 0x02014b50) throw new Error('CDH خراب در آفست ' + p);

    const e = {
      versionMadeBy: buf.readUInt16LE(p + 4),
      versionNeeded: buf.readUInt16LE(p + 6),
      flags: buf.readUInt16LE(p + 8),
      method: buf.readUInt16LE(p + 10),
      time: buf.readUInt16LE(p + 12),
      date: buf.readUInt16LE(p + 14),
      crc: buf.readUInt32LE(p + 16),
      compSize: buf.readUInt32LE(p + 20),
      uncompSize: buf.readUInt32LE(p + 24),
      nameLen: buf.readUInt16LE(p + 28),
      extraLen: buf.readUInt16LE(p + 30),
      commentLen: buf.readUInt16LE(p + 32),
      diskStart: buf.readUInt16LE(p + 34),
      internalAttrs: buf.readUInt16LE(p + 36),
      externalAttrs: buf.readUInt32LE(p + 38),
      localOffset: buf.readUInt32LE(p + 42),
    };

    const nameStart = p + 46;
    e.name = buf.subarray(nameStart, nameStart + e.nameLen);
    e.extra = Buffer.from(buf.subarray(nameStart + e.nameLen, nameStart + e.nameLen + e.extraLen));
    e.comment = Buffer.from(buf.subarray(nameStart + e.nameLen + e.extraLen, nameStart + e.nameLen + e.extraLen + e.commentLen));

    const lo = e.localOffset;
    if (buf.readUInt32LE(lo) !== 0x04034b50) throw new Error('LFH خراب برای ' + e.name.toString());
    const lNameLen = buf.readUInt16LE(lo + 26);
    const lExtraLen = buf.readUInt16LE(lo + 28);
    const dataStart = lo + 30 + lNameLen + lExtraLen;

    e.data = Buffer.from(buf.subarray(dataStart, dataStart + e.compSize));
    entries.push(e);

    p = nameStart + e.nameLen + e.extraLen + e.commentLen;
  }
  return entries;
}

/* ---------- ساخت ورودی جدید از یک فایل ---------- */
function makeEntry(name, filePath) {
  const raw = fs.readFileSync(filePath);
  const deflated = zlib.deflateRawSync(raw, { level: 9 });
  const useDeflate = deflated.length < raw.length;

  const nameBuf = Buffer.from(name, 'utf8');
  const d = new Date();

  return {
    versionMadeBy: 20,
    versionNeeded: 20,
    flags: 0x0800, // UTF-8
    method: useDeflate ? 8 : 0,
    time: ((d.getHours() << 11) | (d.getMinutes() << 5) | (d.getSeconds() >> 1)) & 0xffff,
    date: (((d.getFullYear() - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate()) & 0xffff,
    crc: crc32(raw),
    compSize: useDeflate ? deflated.length : raw.length,
    uncompSize: raw.length,
    name: nameBuf,
    nameLen: nameBuf.length,
    extra: Buffer.alloc(0),
    comment: Buffer.alloc(0),
    diskStart: 0,
    internalAttrs: 0,
    externalAttrs: 0,
    data: useDeflate ? deflated : raw,
  };
}

/* ---------- نوشتن APK هم‌تراز ---------- */
function writeAligned(entries, outPath) {
  const chunks = [];
  let offset = 0;
  const push = (b) => { chunks.push(b); offset += b.length; };

  for (const e of entries) {
    e.newLocalOffset = offset;

    // پدینگ داخل فیلد extra تا داده روی مرز ALIGN بیفتد
    const base = offset + 30 + e.name.length + e.extra.length;
    const pad = (ALIGN - (base % ALIGN)) % ALIGN;

    let extra = e.extra;
    if (pad > 0) extra = Buffer.concat([e.extra, Buffer.alloc(pad)]);

    const lfh = Buffer.alloc(30);
    lfh.writeUInt32LE(0x04034b50, 0);
    lfh.writeUInt16LE(e.versionNeeded, 4);
    lfh.writeUInt16LE(e.flags & ~0x08, 6); // حذف data-descriptor
    lfh.writeUInt16LE(e.method, 8);
    lfh.writeUInt16LE(e.time, 10);
    lfh.writeUInt16LE(e.date, 12);
    lfh.writeUInt32LE(e.crc, 14);
    lfh.writeUInt32LE(e.compSize, 18);
    lfh.writeUInt32LE(e.uncompSize, 22);
    lfh.writeUInt16LE(e.name.length, 26);
    lfh.writeUInt16LE(extra.length, 28);

    push(lfh);
    push(e.name);
    push(extra);
    e.dataStart = offset;
    push(e.data);
  }

  const cdStart = offset;
  for (const e of entries) {
    const cdh = Buffer.alloc(46);
    cdh.writeUInt32LE(0x02014b50, 0);
    cdh.writeUInt16LE(e.versionMadeBy, 4);
    cdh.writeUInt16LE(e.versionNeeded, 6);
    cdh.writeUInt16LE(e.flags & ~0x08, 8);
    cdh.writeUInt16LE(e.method, 10);
    cdh.writeUInt16LE(e.time, 12);
    cdh.writeUInt16LE(e.date, 14);
    cdh.writeUInt32LE(e.crc, 16);
    cdh.writeUInt32LE(e.compSize, 20);
    cdh.writeUInt32LE(e.uncompSize, 24);
    cdh.writeUInt16LE(e.name.length, 28);
    cdh.writeUInt16LE(e.extra.length, 30);
    cdh.writeUInt16LE(e.comment.length, 32);
    cdh.writeUInt16LE(e.diskStart, 34);
    cdh.writeUInt16LE(e.internalAttrs, 36);
    cdh.writeUInt32LE(e.externalAttrs, 38);
    cdh.writeUInt32LE(e.newLocalOffset, 42);

    push(cdh);
    push(e.name);
    push(e.extra);
    push(e.comment);
  }
  const cdSize = offset - cdStart;

  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(0, 4);
  eocd.writeUInt16LE(0, 6);
  eocd.writeUInt16LE(entries.length, 8);
  eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(cdSize, 12);
  eocd.writeUInt32LE(cdStart, 16);
  eocd.writeUInt16LE(0, 20);
  push(eocd);

  fs.writeFileSync(outPath, Buffer.concat(chunks));
  return entries;
}

/* ---------- main ---------- */
const [, , inApk, outApk, ...adds] = process.argv;
if (!inApk || !outApk) {
  console.error('usage: node zipalign.js <in.apk> <out.apk> [name=path ...]');
  process.exit(1);
}

const buf = fs.readFileSync(inApk);
let existing = readEntries(buf);

// فایل‌های اضافی (classes.dex) در ابتدا قرار می‌گیرند
const added = adds.map((a) => {
  const i = a.indexOf('=');
  const name = a.slice(0, i);
  const path = a.slice(i + 1);
  return makeEntry(name, path);
});

let entries = added.concat(existing.filter((e) => e.name.toString() !== 'classes.dex'));

entries = writeAligned(entries, outApk);

// ---------- بررسی ----------
let bad = 0;
for (const e of entries) {
  if (e.dataStart % ALIGN !== 0) {
    console.log('  NOT ALIGNED:', e.name.toString(), e.dataStart);
    bad++;
  }
}
console.log('  entries: ' + entries.length + '   misaligned: ' + bad);
console.log('  wrote:   ' + outApk + '  (' + (fs.statSync(outApk).size / 1024).toFixed(1) + ' KB)');
if (bad > 0) process.exit(2);
