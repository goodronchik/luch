/// Self-contained web portal HTML served when a peer opens the QR URL in a browser.
class WebPortalHtml {
  static String build({required String token}) {
    final safeTokenJson = _jsStringLiteral(token);
    return '''<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Луч — Обмен файлами</title>
  <style>
    :root {
      --bg: #0b1020;
      --card: #141c33;
      --border: #263252;
      --text: #eef2ff;
      --muted: #94a3b8;
      --accent: #38bdf8;
      --accent2: #f59e0b;
      --ok: #34d399;
      --err: #fb7185;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: radial-gradient(circle at top right, #17254a, var(--bg) 60%);
      color: var(--text);
      display: flex;
      justify-content: center;
      padding: 20px;
    }
    .wrap {
      width: 100%;
      max-width: 620px;
    }
    .header {
      display: flex;
      align-items: center;
      gap: 12px;
      margin-bottom: 18px;
    }
    .logo {
      width: 44px;
      height: 44px;
      border-radius: 12px;
      background: linear-gradient(135deg, var(--accent), var(--accent2));
      display: grid;
      place-items: center;
      font-weight: 800;
      color: #08101f;
      font-size: 20px;
    }
    h1 { margin: 0; font-size: 22px; }
    .sub { color: var(--muted); font-size: 13px; margin-top: 2px; }
    .card {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 18px;
      padding: 18px;
      box-shadow: 0 12px 32px rgba(0, 0, 0, 0.35);
    }
    .file-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      padding: 12px 0;
      border-bottom: 1px solid var(--border);
    }
    .file-row:last-child { border-bottom: none; }
    .file-name {
      font-weight: 600;
      word-break: break-word;
    }
    .file-size {
      color: var(--muted);
      font-size: 12px;
      margin-top: 3px;
    }
    .btn {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      border: none;
      border-radius: 10px;
      padding: 10px 16px;
      font-weight: 600;
      font-size: 14px;
      cursor: pointer;
      text-decoration: none;
      background: var(--accent);
      color: #061322;
      white-space: nowrap;
    }
    .btn:disabled { opacity: 0.5; cursor: not-allowed; }
    .drop {
      border: 2px dashed var(--border);
      border-radius: 14px;
      padding: 28px 16px;
      text-align: center;
      margin-bottom: 14px;
      transition: border-color .15s, background .15s;
    }
    .drop.active {
      border-color: var(--accent);
      background: rgba(56, 189, 248, 0.08);
    }
    progress {
      width: 100%;
      height: 10px;
      border-radius: 999px;
      overflow: hidden;
      margin-top: 10px;
    }
    .status { margin-top: 10px; font-size: 13px; color: var(--muted); }
    .status.ok { color: var(--ok); }
    .status.err { color: var(--err); }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="header">
      <div class="logo">Л</div>
      <div>
        <h1>Луч</h1>
        <div class="sub" id="deviceLabel">Подключение к устройству...</div>
      </div>
    </div>
    <div class="card" id="mainCard">Загрузка сессии...</div>
  </div>

  <script>
    const TOKEN = $safeTokenJson;

    function formatBytes(bytes) {
      if (bytes < 1024) return bytes + ' Б';
      const units = ['КБ', 'МБ', 'ГБ', 'ТБ'];
      let val = bytes;
      let idx = -1;
      while (val >= 1024 && idx < units.length - 1) {
        val /= 1024;
        idx++;
      }
      return val.toFixed(val >= 10 ? 1 : 2) + ' ' + units[idx];
    }

    async function init() {
      const card = document.getElementById('mainCard');
      const deviceLabel = document.getElementById('deviceLabel');
      try {
        const res = await fetch('/api/v1/session?token=' + encodeURIComponent(TOKEN));
        if (!res.ok) throw new Error('Сессия не найдена или остановлена');
        const session = await res.json();
        deviceLabel.textContent = session.deviceName + ' • ' +
          (session.mode === 'send' ? 'Раздача файлов' : 'Приём файлов');

        if (session.mode === 'send') {
          renderSendView(card, session);
        } else {
          renderReceiveView(card);
        }
      } catch (err) {
        card.textContent = '';
        const p = document.createElement('div');
        p.className = 'status err';
        p.textContent = err.message || 'Ошибка подключения';
        card.appendChild(p);
      }
    }

    function renderSendView(card, session) {
      card.textContent = '';
      if (!session.files || session.files.length === 0) {
        const empty = document.createElement('div');
        empty.className = 'sub';
        empty.textContent = 'Нет выбранных файлов.';
        card.appendChild(empty);
        return;
      }
      for (const file of session.files) {
        const row = document.createElement('div');
        row.className = 'file-row';

        const meta = document.createElement('div');
        const nameEl = document.createElement('div');
        nameEl.className = 'file-name';
        nameEl.textContent = file.name;
        const sizeEl = document.createElement('div');
        sizeEl.className = 'file-size';
        sizeEl.textContent = formatBytes(file.sizeBytes || 0);
        meta.appendChild(nameEl);
        meta.appendChild(sizeEl);

        const link = document.createElement('a');
        link.className = 'btn';
        link.textContent = 'Скачать';
        link.href = '/api/v1/files/' + encodeURIComponent(file.id) +
          '?token=' + encodeURIComponent(TOKEN);
        link.setAttribute('download', file.name);

        row.appendChild(meta);
        row.appendChild(link);
        card.appendChild(row);
      }
    }

    function renderReceiveView(card) {
      card.textContent = '';
      const drop = document.createElement('div');
      drop.className = 'drop';
      drop.textContent = 'Перетащите файлы сюда или выберите с устройства';

      const input = document.createElement('input');
      input.type = 'file';
      input.multiple = true;
      input.style.display = 'none';

      const btn = document.createElement('button');
      btn.className = 'btn';
      btn.type = 'button';
      btn.textContent = 'Выбрать файлы и отправить';
      btn.onclick = () => input.click();

      const prog = document.createElement('progress');
      prog.max = 100;
      prog.value = 0;
      prog.style.display = 'none';

      const status = document.createElement('div');
      status.className = 'status';

      drop.addEventListener('dragover', (e) => {
        e.preventDefault();
        drop.classList.add('active');
      });
      drop.addEventListener('dragleave', () => drop.classList.remove('active'));
      drop.addEventListener('drop', (e) => {
        e.preventDefault();
        drop.classList.remove('active');
        if (e.dataTransfer && e.dataTransfer.files.length > 0) {
          uploadFiles(e.dataTransfer.files, btn, prog, status);
        }
      });

      input.onchange = () => {
        if (input.files && input.files.length > 0) {
          uploadFiles(input.files, btn, prog, status);
        }
      };

      card.appendChild(drop);
      card.appendChild(input);
      card.appendChild(btn);
      card.appendChild(prog);
      card.appendChild(status);
    }

    async function uploadFiles(fileList, btn, prog, status) {
      btn.disabled = true;
      prog.style.display = 'block';
      const files = Array.from(fileList);
      try {
        for (let i = 0; i < files.length; i++) {
          const f = files[i];
          status.className = 'status';
          status.textContent = 'Отправка (' + (i + 1) + '/' + files.length + '): ' + f.name;
          await uploadSingle(f, (pct) => { prog.value = pct; });
        }
        status.className = 'status ok';
        status.textContent = 'Готово! Отправлено файлов: ' + files.length;
      } catch (err) {
        status.className = 'status err';
        status.textContent = err.message || 'Ошибка при отправке';
      } finally {
        btn.disabled = false;
      }
    }

    function uploadSingle(file, onProgress) {
      return new Promise((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        const url = '/api/v1/upload?token=' + encodeURIComponent(TOKEN) +
          '&filename=' + encodeURIComponent(file.name);
        xhr.open('POST', url, true);
        xhr.setRequestHeader('Content-Type', 'application/octet-stream');
        xhr.upload.onprogress = (e) => {
          if (e.lengthComputable && e.total > 0) {
            onProgress(Math.round((e.loaded / e.total) * 100));
          }
        };
        xhr.onload = () => {
          if (xhr.status >= 200 && xhr.status < 300) resolve();
          else reject(new Error('Сервер вернул ошибку ' + xhr.status));
        };
        xhr.onerror = () => reject(new Error('Сетевая ошибка при передаче'));
        xhr.send(file);
      });
    }

    init();
  </script>
</body>
</html>''';
  }

  static String _jsStringLiteral(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r')
        .replaceAll('<', r'\u003c')
        .replaceAll('>', r'\u003e');
    return "'$escaped'";
  }
}
