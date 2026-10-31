export const ui = `<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>État du déploiement</title>
  <style>
    :root { color-scheme: dark; font-family: system-ui, sans-serif; }
    body { max-width: 900px; margin: 0 auto; padding: 48px 20px; background: #0b1020; color: #eef2ff; }
    h1 { margin-bottom: 8px; } .subtitle { color: #94a3b8; margin-top: 0; }
    #connection { display: inline-block; margin: 16px 0 28px; padding: 6px 10px; border-radius: 99px; background: #334155; }
    #grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 16px; }
    article { padding: 20px; border: 1px solid #26314d; border-radius: 12px; background: #11182b; }
    article.ok { border-color: #16a34a; } article.error { border-color: #dc2626; }
    article.starting { border-color: #d97706; }
    .state { font-weight: 700; text-transform: uppercase; }
    .ok .state { color: #4ade80; } .error .state { color: #f87171; } .starting .state { color: #fbbf24; }
    small { color: #94a3b8; } p { min-height: 2.5em; }
  </style>
</head>
<body>
  <h1>Test de déploiement</h1>
  <p class="subtitle">État en temps réel des communications</p>
  <span id="connection">WebSocket : connexion…</span>
  <main id="grid"></main>
  <script>
    const grid = document.querySelector('#grid');
    const connection = document.querySelector('#connection');
    const escapeHtml = (value) => { const el = document.createElement('span'); el.textContent = value; return el.innerHTML; };
    const render = (statuses) => {
      grid.innerHTML = Object.values(statuses).sort((a, b) => a.name.localeCompare(b.name)).map((item) =>
        '<article class="' + item.state + '"><h2>' + escapeHtml(item.name) + '</h2>' +
        '<div class="state">' + escapeHtml(item.state) + '</div><p>' + escapeHtml(item.message) + '</p>' +
        '<small>' + new Date(item.updatedAt).toLocaleString('fr-FR') + '</small></article>'
      ).join('');
    };
    const connect = () => {
      const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
      const socket = new WebSocket(protocol + '//' + location.host + '/ws');
      socket.onopen = () => { connection.textContent = 'WebSocket : connecté'; };
      socket.onmessage = (event) => render(JSON.parse(event.data));
      socket.onclose = () => { connection.textContent = 'WebSocket : reconnexion…'; setTimeout(connect, 1500); };
    };
    connect();
  </script>
</body>
</html>`;
