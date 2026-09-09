'use strict';
// Tiny PUT-based upload endpoint. dsh itself has no upload/attachment RPC —
// confirmed by inspecting the installed @deepseek-ai/dsh package directly:
// its host.* RPC surface is listDirectory/pickDirectory/createDirectory/
// openPath/describe, and workspace.* is create/list/rename/delete/etc. —
// directory browsing and workspace registration only, nothing that accepts
// file *content* from the browser. This is the actual way a participant
// gets an external file into an agent's hands: PUT it here, and it shows up
// at /workspace/uploads/<name> in every team's DeepSeek Harness container
// (see docker-compose.yml's dsh-upload volume) without dsh needing to know
// anything happened.
//
// No auth of its own, no per-team isolation — reached only via each team's
// Caddy subdomain (already Basic Auth-gated) at /upload/*, and intentionally
// a single shared drop folder: every team can see and write every upload.
const http = require('http');
const fs = require('fs');
const path = require('path');

const UPLOAD_DIR = '/uploads';
const MAX_BYTES = 200 * 1024 * 1024; // generous for a CSV/JSON/PDF drop, not a general dumping ground

const INDEX_HTML = `<!doctype html>
<html><head><meta charset="utf-8"><title>Upload a file</title>
<style>
body{font-family:system-ui,sans-serif;max-width:640px;margin:2rem auto;padding:0 1rem}
#drop{border:2px dashed #888;border-radius:8px;padding:3rem;text-align:center;color:#555}
#drop.over{background:#eef}
#status{margin-top:1rem;white-space:pre-wrap;font-family:monospace}
</style></head>
<body>
<h1>Upload a file</h1>
<p>Files land in every team's DeepSeek Harness workspace at
<code>/workspace/uploads/&lt;filename&gt;</code> and are visible to everyone —
this is a shared drop folder, not private to your team.</p>
<div id="drop">Drop a file here, or <input type="file" id="picker"></div>
<div id="status"></div>
<script>
const drop = document.getElementById('drop');
const status = document.getElementById('status');
const picker = document.getElementById('picker');

function upload(file) {
  status.textContent = 'Uploading ' + file.name + ' (' + file.size + ' bytes)...';
  fetch('./' + encodeURIComponent(file.name), { method: 'PUT', body: file })
    .then(async r => {
      const text = await r.text();
      status.textContent = text;
    })
    .catch(e => { status.textContent = 'Error: ' + e; });
}

drop.addEventListener('dragover', e => { e.preventDefault(); drop.classList.add('over'); });
drop.addEventListener('dragleave', () => drop.classList.remove('over'));
drop.addEventListener('drop', e => {
  e.preventDefault();
  drop.classList.remove('over');
  if (e.dataTransfer.files[0]) upload(e.dataTransfer.files[0]);
});
picker.addEventListener('change', () => { if (picker.files[0]) upload(picker.files[0]); });
</script>
</body></html>`;

function safeName(rawUrl) {
  let name;
  try {
    name = decodeURIComponent(rawUrl.split('?')[0]);
  } catch {
    return null;
  }
  name = name.replace(/^\/+/, '');
  if (!name) return null;
  if (name.includes('/') || name.includes('\\') || name.includes('\0')) return null;
  if (name === '.' || name === '..') return null;
  if (name.length > 200) return null;
  return name;
}

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && (req.url === '/' || req.url === '')) {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(INDEX_HTML);
    return;
  }

  if (req.method !== 'PUT') {
    res.writeHead(405, { 'content-type': 'text/plain' });
    res.end('method not allowed (PUT a file to /upload/<filename>)');
    return;
  }

  const name = safeName(req.url);
  if (!name) {
    res.writeHead(400, { 'content-type': 'text/plain' });
    res.end('invalid filename');
    return;
  }

  const declaredLen = Number(req.headers['content-length'] || 0);
  if (declaredLen > MAX_BYTES) {
    res.writeHead(413, { 'content-type': 'text/plain' });
    res.end('file too large (max ' + MAX_BYTES + ' bytes)');
    req.destroy();
    return;
  }

  const tmpPath = path.join(UPLOAD_DIR, '.' + name + '.' + process.pid + '.tmp');
  const finalPath = path.join(UPLOAD_DIR, name);
  const out = fs.createWriteStream(tmpPath);
  let received = 0;
  let aborted = false;

  const abort = (status, message) => {
    if (aborted) return;
    aborted = true;
    out.destroy();
    fs.unlink(tmpPath, () => {});
    if (!res.headersSent) {
      res.writeHead(status, { 'content-type': 'text/plain' });
      res.end(message);
    }
    req.destroy();
  };

  req.on('data', chunk => {
    received += chunk.length;
    if (received > MAX_BYTES) abort(413, 'file too large (max ' + MAX_BYTES + ' bytes)');
  });
  req.on('error', () => abort(400, 'upload interrupted'));
  out.on('error', err => abort(500, 'write failed: ' + err.message));

  req.pipe(out);

  out.on('finish', () => {
    if (aborted) return;
    fs.rename(tmpPath, finalPath, err => {
      if (err) {
        res.writeHead(500, { 'content-type': 'text/plain' });
        res.end('write failed: ' + err.message);
        return;
      }
      res.writeHead(200, { 'content-type': 'text/plain' });
      res.end(
        'OK: uploaded ' + name + ' (' + received + ' bytes)\n' +
        'Visible in every team\'s DeepSeek Harness at /workspace/uploads/' + name + '\n' +
        'Browsable at /uploads/' + name
      );
    });
  });
});

server.listen(8081, '0.0.0.0', () => {
  console.log('dsh-upload listening on :8081, writing into ' + UPLOAD_DIR);
});
