'use strict';
// Menjalankan seluruh suite; berhenti dengan kode 1 bila ada yang gagal.
const { spawnSync } = require('child_process');
const path = require('path');
const suites = [['Protokol alat', 'protocol.test.js'], ['API (QA end-to-end)', 'smoke.test.js'], ['Tautan USB (port palsu)', 'usb-link.test.js'], ['I/O serial nyata (pty)', 'tty.test.js']];
let failed = 0;
for (const [name, file] of suites) {
  console.log(`\n===== ${name} =====`);
  const r = spawnSync(process.execPath, [path.join(__dirname, file)], { stdio: 'inherit', timeout: 120000 });
  if (r.status !== 0) { failed++; console.error(`>>> GAGAL: ${file} (kode ${r.status})`); }
}
console.log(failed ? `\n${failed} suite GAGAL` : '\nSEMUA SUITE LULUS');
process.exit(failed ? 1 : 0);
