#!/usr/bin/env python3
"""Niet-publieke wiki-site voor de kennisbank.

Leest alles rechtstreeks van de lokale schijf: kennisbank/wiki/*.md (staat
alleen op deze Pi, nooit op GitHub) en TODO.md (een lokale kopie naast
app.py, ververst met refresh-todo.sh wanneer nodig). Geen netwerkverkeer
meer terwijl de site draait — werkt ook zonder internetverbinding. Bouwt
de paginastructuur door vanuit wiki/index.md de markdown-links te volgen
(dezelfde regel als de "geen wees-pagina's"-controle in
kennisbank/Claude.md), en serveert dat als mobielvriendelijke HTML met een
zoekfunctie. Geen database, alleen de Python-standaardbibliotheek — met
een enkele uitzondering: het uploaden van een PDF-recept (vanaf de iPhone)
gebruikt de externe package "pypdf" om de tekst eruit te halen, zie
extract_upload_text() en de docker run-commando's in setup-wiki-site.sh /
update-wiki-site.sh die deze installeren.

Bedoeld om uitsluitend bereikbaar te zijn via `tailscale serve` (tailnet-
only), nooit via `tailscale funnel` (publiek internet).
"""
import html
import io
import json
import os
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

KENNISBANK_DIR = os.environ.get("KENNISBANK_DIR", os.path.expanduser("~/kennisbank"))
WIKI_ROOT = "kennisbank/wiki/index.md"
TODO_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "TODO.md")
CATEGORY_SLUGS = ["persoonlijk", "praktisch", "prompts", "koken"]
PORT = 8090
CACHE_TTL = 300  # seconden
RECENT_COUNT = 8

# Dezelfde commandoherkenning als Telegram, maar dan rechtstreeks vanaf
# deze website aangeroepen (zie docs/angie/patch-cli-bypass.sh).
N8N_CLI_URL = os.environ.get("N8N_CLI_URL", "http://100.77.5.104:5678/webhook/angie-cli")
WHISPER_URL = os.environ.get("WHISPER_URL", "http://100.68.46.126:27125/transcribe")
# Het herschrijven van een recept (Reflux-Filter-Protocol) kan op het lokale
# model tot ~150 seconden duren, /onderzoek tot ~135 seconden — een korte
# timeout hier laat de chat dan onterecht "timed out" melden terwijl n8n
# nog gewoon doorwerkt.
CHAT_HTTP_TIMEOUT = 200


def call_n8n_cli(text, bijlage=None):
    """Stuurt tekst naar dezelfde commandoherkenning als Telegram/CLI en
    geeft het antwoord terug. Gooit een Exception met een leesbare reden
    als dat niet lukt (n8n niet bereikbaar, timeout, etc.). 'bijlage' is het
    kennisbank/wiki/-relatieve pad van een gestaged origineel bestand (zie
    save_attachment), zodat n8n het kan verplaatsen naar de juiste rubriek
    en linken vanuit de nieuwe pagina."""
    body_obj = {"text": text}
    if bijlage:
        body_obj["bijlage"] = bijlage
    body = json.dumps(body_obj).encode("utf-8")
    req = urllib.request.Request(
        N8N_CLI_URL, data=body, method="POST",
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=CHAT_HTTP_TIMEOUT) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    return data.get("reply", "")


def call_whisper(audio_bytes):
    """Stuurt audio (willekeurig formaat, ffmpeg/whisper bepaalt zelf de
    inhoud, niet de bestandsnaam) naar de Whisper-server en geeft de
    getranscribeerde tekst terug."""
    req = urllib.request.Request(
        WHISPER_URL, data=audio_bytes, method="POST",
        headers={"Content-Type": "application/octet-stream"},
    )
    with urllib.request.urlopen(req, timeout=CHAT_HTTP_TIMEOUT) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    return data.get("text", "")


class UploadDecodeError(Exception):
    """Geeft een voor de gebruiker leesbare reden waarom een geupload
    bestand niet naar tekst omgezet kon worden."""


def extract_upload_text(raw_bytes, filename):
    """Zet een geupload bestand om naar platte tekst. PDF (herkend aan de
    %PDF-magic bytes, niet aan de bestandsnaam) gaat via pypdf; alles
    anders moet gewoon leesbare UTF-8-tekst zijn (.txt/.md)."""
    if raw_bytes[:5] == b"%PDF-":
        try:
            import pypdf
        except ImportError:
            raise UploadDecodeError(
                "PDF-ondersteuning is niet geinstalleerd in deze container. "
                "Draai update-wiki-site.sh opnieuw op de Pi (die installeert pypdf)."
            )
        try:
            reader = pypdf.PdfReader(io.BytesIO(raw_bytes))
            text = "\n\n".join(page.extract_text() or "" for page in reader.pages)
        except Exception as e:
            raise UploadDecodeError(f"PDF '{filename}' kon niet gelezen worden ({e}).")
        text = text.strip()
        if not text:
            raise UploadDecodeError(
                f"Geen tekst gevonden in '{filename}' — dit is waarschijnlijk een gescande "
                "PDF (foto's van tekst, geen echte tekstlaag). Daar is geen OCR/vision-model "
                "voor gekoppeld, dus typ of plak de inhoud zelf."
            )
        return text
    try:
        return raw_bytes.decode("utf-8")
    except UnicodeDecodeError:
        raise UploadDecodeError(
            f"'{filename}' is geen leesbaar tekstbestand. Tekstbestanden (.txt/.md) en "
            "PDF's met een tekstlaag kunnen verwerkt worden — foto's nog niet, daarvoor is "
            "geen vision-model gekoppeld."
        )


def save_attachment(raw_bytes, filename):
    """Bewaart het originele geuploade bestand (bv. een PDF-factuur) in een
    staging-map in de kennisbank. Tekst-extractie (extract_upload_text)
    verliest opmaak/lay-out, en voor facturen/tickets/garantiebewijzen moet
    je later het origineel kunnen tonen aan de belastingdienst of een
    winkel — dus dat origineel moet ergens blijven staan, niet alleen de
    geextraheerde tekst. n8n verplaatst dit bestand vervolgens (zie de
    'bijlage'-afhandeling in de workflow) naar de map van de uiteindelijke
    rubriek en linkt het vanuit de nieuwe pagina. Geeft het kennisbank/wiki/
    -relatieve pad terug, of None als opslaan niet lukte (dan gaat het
    verzoek door zonder bijlage, in plaats van helemaal te mislukken)."""
    safe_name = re.sub(r"[^A-Za-z0-9._-]", "_", filename) or "bestand"
    staged_name = time.strftime("%Y%m%d%H%M%S") + "-" + safe_name
    staging_dir = os.path.join(KENNISBANK_DIR, "wiki", "_bijlagen")
    try:
        os.makedirs(staging_dir, exist_ok=True)
        with open(os.path.join(staging_dir, staged_name), "wb") as f:
            f.write(raw_bytes)
        return "_bijlagen/" + staged_name
    except OSError:
        return None


_cache_lock = threading.Lock()
_cache = {"pages": {}, "todo": "", "mtimes": {}, "built_at": 0.0}


def fetch_local_todo():
    """Leest de lokale TODO.md-kopie naast app.py (nooit GitHub)."""
    try:
        with open(TODO_PATH, "r", encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def local_wiki_path(path):
    rel = path[len("kennisbank/"):]
    return os.path.join(KENNISBANK_DIR, rel)


def fetch_local_wiki(path):
    """Leest een kennisbank/wiki/*.md-pad van de lokale schijf (nooit GitHub)."""
    try:
        with open(local_wiki_path(path), "r", encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


def crawl_wiki():
    """Volgt links vanuit wiki/index.md (en de categoriepagina's) om alle
    wiki-pagina's te vinden. Geeft ook de laatste-wijzigingstijd per pagina
    terug, gebruikt om de homepage te sorteren op recentste toevoeging."""
    pages = {}
    mtimes = {}
    seen = set()
    queue = [WIKI_ROOT] + [f"kennisbank/wiki/{slug}.md" for slug in CATEGORY_SLUGS]
    while queue:
        path = queue.pop(0)
        if path in seen:
            continue
        seen.add(path)
        text = fetch_local_wiki(path)
        if text is None:
            continue
        pages[path] = text
        try:
            mtimes[path] = os.stat(local_wiki_path(path)).st_mtime
        except OSError:
            pass
        base_dir = os.path.dirname(path)
        for _label, target in LINK_RE.findall(text):
            target = target.strip()
            if target.startswith(("http://", "https://", "#")):
                continue
            if not target.endswith(".md"):
                continue
            resolved = os.path.normpath(os.path.join(base_dir, target))
            if resolved.startswith("kennisbank/wiki/") and resolved not in seen:
                queue.append(resolved)
    return pages, mtimes


def get_cache():
    with _cache_lock:
        if time.time() - _cache["built_at"] > CACHE_TTL:
            pages, mtimes = crawl_wiki()
            todo = fetch_local_todo() or "_TODO.md kon niet geladen worden._"
            if pages:
                _cache["pages"] = pages
                _cache["mtimes"] = mtimes
                _cache["todo"] = todo
                _cache["built_at"] = time.time()
        return _cache["pages"], _cache["todo"], _cache["mtimes"]


def invalidate_cache():
    with _cache_lock:
        _cache["built_at"] = 0.0


def remove_links_to(pages, deleted_path):
    """Knipt regels die naar deleted_path linken uit alle andere wiki-
    bestanden (bijv. de bullet in een categoriepagina), zodat verwijderen
    geen dode links achterlaat."""
    for path, text in pages.items():
        if path == deleted_path:
            continue
        base_dir = os.path.dirname(path)
        new_lines = []
        changed = False
        for line in text.split("\n"):
            targets = [t.strip() for _label, t in LINK_RE.findall(line)]
            points_to_deleted = any(
                not t.startswith(("http://", "https://", "#"))
                and t.endswith(".md")
                and os.path.normpath(os.path.join(base_dir, t)) == deleted_path
                for t in targets
            )
            if points_to_deleted:
                changed = True
                continue
            new_lines.append(line)
        if changed:
            try:
                with open(local_wiki_path(path), "w", encoding="utf-8") as f:
                    f.write("\n".join(new_lines))
            except OSError:
                pass


def wiki_path_to_route(path):
    rel = path[len("kennisbank/wiki/"):-len(".md")]
    return "" if rel == "index" else rel


def route_to_wiki_path(route):
    rel = route.strip("/") or "index"
    return f"kennisbank/wiki/{rel}.md"


INLINE_RE = [
    (re.compile(r"\*\*([^*]+)\*\*"), r"<strong>\1</strong>"),
    (re.compile(r"~~([^~]+)~~"), r"<del>\1</del>"),
    (re.compile(r"`([^`]+)`"), r"<code>\1</code>"),
]


def render_inline(text, base_dir):
    text = html.escape(text)

    def link_sub(m):
        label, target = m.group(1), m.group(2).strip()
        if target.startswith(("http://", "https://")):
            return f'<a href="{html.escape(target)}" target="_blank" rel="noopener">{label}</a>'
        if target.endswith(".md"):
            resolved = os.path.normpath(os.path.join(base_dir, target))
            return f'<a href="/wiki/{wiki_path_to_route(resolved)}">{label}</a>'
        return label

    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link_sub, text)
    for pattern, repl in INLINE_RE:
        text = pattern.sub(repl, text)
    return text


def group_into_blocks(text):
    """Groept zacht-afgebroken regels (prozastijl, ~80 kolommen) tot logische
    blokken: een alinea of lijst-item loopt door tot de volgende lege regel,
    kopregel, lijst-bullet of horizontale lijn."""
    blocks = []
    current = None
    for raw_line in text.replace("\r\n", "\n").split("\n"):
        stripped = raw_line.strip()
        if not stripped:
            current = None
            continue
        heading_m = re.match(r"^(#{1,3})\s+(.*)$", stripped)
        if heading_m:
            current = None
            blocks.append([f"h{len(heading_m.group(1))}", heading_m.group(2)])
            continue
        if stripped.startswith("---"):
            current = None
            continue
        bullet_m = re.match(r"^[-*]\s+(.*)$", stripped)
        if bullet_m:
            current = ["li", bullet_m.group(1)]
            blocks.append(current)
            continue
        if current is not None and current[0] in ("p", "li"):
            current[1] += " " + stripped
        else:
            current = ["p", stripped]
            blocks.append(current)
    return blocks


def markdown_to_html(text, base_dir=""):
    out = []
    in_list = False
    for kind, content in group_into_blocks(text):
        if kind == "li":
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{render_inline(content, base_dir)}</li>")
            continue
        if in_list:
            out.append("</ul>")
            in_list = False
        if kind == "p":
            out.append(f"<p>{render_inline(content, base_dir)}</p>")
        else:
            out.append(f"<{kind}>{render_inline(content, base_dir)}</{kind}>")
    if in_list:
        out.append("</ul>")
    return "\n".join(out)


def extract_title(text, fallback):
    m = re.search(r"^#\s+(.*)$", text, re.MULTILINE)
    if m:
        return m.group(1)
    # Geen "# titel" gevonden (bv. een ouder paginatype dat per ongeluk geen
    # kop toevoegt) -- val terug op de eerste niet-lege tekstregel in plaats
    # van het kale bestandspad, anders toont "Recent toegevoegd" alleen een
    # onleesbare tijdstempel zonder enig idee waar de pagina over gaat.
    body = re.sub(r"^---\n.*?\n---\n", "", text, count=1, flags=re.DOTALL)
    for line in body.splitlines():
        line = line.strip()
        if line and not line.startswith("[Bekijk origineel]"):
            preview = strip_markdown(line)
            if preview:
                return preview[:60]
    return fallback


def strip_markdown(text):
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"[#*`_~]", "", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


PAGE_TEMPLATE = """<!doctype html>
<html lang="nl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>
  :root {{ color-scheme: light dark; }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0; padding: 1rem 1rem 3rem;
    font-family: -apple-system, system-ui, sans-serif;
    font-size: 17px; line-height: 1.5;
    max-width: 38rem; margin-inline: auto;
  }}
  h1 {{ font-size: 1.5rem; margin-top: 1.2rem; }}
  h2 {{ font-size: 1.2rem; margin-top: 1.4rem; }}
  h3 {{ font-size: 1.05rem; }}
  a {{ color: #0a5ea8; text-decoration: none; }}
  a:active {{ opacity: 0.6; }}
  ul {{ padding-left: 1.2rem; }}
  li {{ margin-bottom: 0.4rem; }}
  .top-nav {{
    display: flex; flex-wrap: wrap; gap: 0.4rem 0.9rem;
    margin-bottom: 1.2rem; font-size: 0.92rem;
  }}
  form.search {{ display: flex; gap: 0.5rem; margin-bottom: 1.5rem; }}
  form.search input[type=text] {{
    flex: 1; padding: 0.6rem; font-size: 1rem;
    border: 1px solid #999; border-radius: 8px;
  }}
  form.search button {{
    padding: 0.6rem 1rem; font-size: 1rem; border: none;
    border-radius: 8px; background: #0a5ea8; color: white;
  }}
  .result {{ margin-bottom: 1rem; }}
  .result .snippet {{ color: #666; font-size: 0.92rem; }}
  .page-actions {{
    display: flex; flex-wrap: wrap; gap: 0.6rem; align-items: center;
    margin-top: 2rem; padding-top: 1rem; border-top: 1px solid #999;
  }}
  .page-actions form {{ margin: 0; }}
  .page-actions button {{
    padding: 0.5rem 0.9rem; font-size: 0.95rem; border-radius: 8px;
    border: 1px solid #999; background: transparent; color: #0a5ea8;
  }}
  .page-actions button.danger {{ border-color: #c33; color: #c33; }}
  .chat-box {{
    margin: 1.2rem 0 1.8rem; border: 1px solid #999; border-radius: 10px;
    padding: 0.8rem;
  }}
  .chat-log {{
    max-height: 55vh; overflow-y: auto; display: flex;
    flex-direction: column; gap: 0.5rem; margin-bottom: 0.6rem;
  }}
  .chat-bubble {{
    padding: 0.5rem 0.7rem; border-radius: 10px; max-width: 90%;
    white-space: pre-wrap; word-break: break-word;
  }}
  .chat-bubble.user {{ align-self: flex-end; background: #0a5ea8; color: white; }}
  .chat-bubble.angie {{ align-self: flex-start; background: rgba(128,128,128,0.18); }}
  .chat-bubble.error {{ align-self: flex-start; background: rgba(204,51,51,0.15); color: #c33; }}
  .chat-input-row {{ display: flex; gap: 0.4rem; align-items: flex-end; }}
  .chat-input-row textarea {{
    flex: 1; padding: 0.6rem; font-size: 1rem; border: 1px solid #999;
    border-radius: 8px; resize: none; font-family: inherit;
  }}
  .chat-input-row button {{
    padding: 0.6rem 0.8rem; font-size: 1.1rem; border: none;
    border-radius: 8px; background: #0a5ea8; color: white; flex-shrink: 0;
  }}
  .chat-input-row button.secondary {{
    background: transparent; border: 1px solid #999; color: inherit;
  }}
  .chat-input-row button.secondary.recording {{ background: #c33; border-color: #c33; color: white; }}
  .chat-status {{ min-height: 1.2rem; font-size: 0.85rem; color: #666; margin: 0.3rem 0 0; }}
</style>
</head>
<body>
<div class="top-nav">
  <a href="/">Wiki</a>
  <a href="/wiki/persoonlijk">Persoonlijk</a>
  <a href="/wiki/praktisch">Praktisch</a>
  <a href="/wiki/prompts">Prompts</a>
  <a href="/wiki/koken">Koken</a>
  <a href="/todo">Todo</a>
</div>
{body}
<script>
function copyRaw(id, btn) {{
  var el = document.getElementById(id);
  navigator.clipboard.writeText(el.value).then(function() {{
    var orig = btn.textContent;
    btn.textContent = 'Gekopieerd';
    setTimeout(function() {{ btn.textContent = orig; }}, 1500);
  }});
}}
function shareRaw(id) {{
  var el = document.getElementById(id);
  navigator.share({{ text: el.value }});
}}
function shareLastReply() {{
  if (window.__lastAngieReply) navigator.share({{ text: window.__lastAngieReply }});
}}
document.querySelectorAll('.share-btn').forEach(function(b) {{
  if (navigator.share) b.hidden = false;
}});
</script>
</body>
</html>"""


def render_page(title, body):
    return PAGE_TEMPLATE.format(title=html.escape(title), body=body)


def render_search_form(query=""):
    q = html.escape(query)
    return (
        f'<form class="search" action="/zoek" method="get">'
        f'<input type="text" name="q" value="{q}" placeholder="Zoek in de wiki...">'
        f'<button type="submit">Zoek</button></form>'
    )


def render_page_actions(route, raw_text):
    """Kopieer/deel-knoppen (rauwe markdown, opmaak blijft behouden) en een
    verwijderknop, voor onder een losse wiki-pagina."""
    raw_id = "raw-" + re.sub(r"[^a-zA-Z0-9_-]", "-", route)
    escaped = html.escape(raw_text)
    route_attr = html.escape(route, quote=True)
    return f"""
<div class="page-actions">
  <textarea id="{raw_id}" hidden>{escaped}</textarea>
  <button type="button" onclick="copyRaw('{raw_id}', this)">Kopieer</button>
  <button type="button" class="share-btn" onclick="shareRaw('{raw_id}')" hidden>Delen</button>
  <form method="post" action="/verwijder" onsubmit="return confirm('Deze pagina definitief verwijderen?');">
    <input type="hidden" name="route" value="{route_attr}">
    <button type="submit" class="danger">Verwijderen</button>
  </form>
</div>"""


CHAT_HTML = """
<div class="chat-box">
  <div id="chat-log" class="chat-log"></div>
  <div class="chat-input-row">
    <textarea id="chat-text" rows="1" placeholder="Schrijf iets, bv. /taken of een vraag..."></textarea>
    <button type="button" id="chat-mic" class="secondary" title="Inspreken">&#127908;</button>
    <button type="button" id="chat-upload-btn" class="secondary" title="Bestand uploaden">&#128206;</button>
    <input type="file" id="chat-file" hidden accept=".txt,.md,.markdown,text/plain,.pdf,application/pdf">
    <button type="button" id="chat-send" title="Versturen">&#10148;</button>
  </div>
  <p id="chat-status" class="chat-status"></p>
  <button type="button" class="share-btn" onclick="shareLastReply()" hidden>Laatste antwoord delen</button>
</div>
<script>
(function() {
  var log = document.getElementById('chat-log');
  var input = document.getElementById('chat-text');
  var sendBtn = document.getElementById('chat-send');
  var micBtn = document.getElementById('chat-mic');
  var uploadBtn = document.getElementById('chat-upload-btn');
  var fileInput = document.getElementById('chat-file');
  var status = document.getElementById('chat-status');
  var shareBtn = document.querySelector('.chat-box .share-btn');

  function addBubble(role, text) {
    var div = document.createElement('div');
    div.className = 'chat-bubble ' + role;
    div.textContent = text;
    log.appendChild(div);
    log.scrollTop = log.scrollHeight;
    return div;
  }

  function onReply(data) {
    status.textContent = '';
    if (data.error) { addBubble('error', data.error); return; }
    if (data.transcript) { addBubble('user', data.transcript); }
    addBubble('angie', data.reply);
    window.__lastAngieReply = data.reply;
    if (shareBtn && navigator.share) shareBtn.hidden = false;
  }

  function onFail(e) {
    status.textContent = '';
    addBubble('error', 'Verbinding mislukt: ' + e.message);
  }

  function postJson(url, opts) {
    return fetch(url, opts).then(function(r) { return r.json(); });
  }

  function sendText(text) {
    if (!text) return;
    addBubble('user', text);
    status.textContent = 'Bezig... (kan bij recepten of onderzoek een paar minuten duren)';
    postJson('/api/chat', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({text: text})
    }).then(onReply).catch(onFail);
  }

  sendBtn.addEventListener('click', function() {
    var text = input.value.trim();
    input.value = '';
    sendText(text);
  });
  input.addEventListener('keydown', function(e) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendBtn.click();
    }
  });

  uploadBtn.addEventListener('click', function() { fileInput.click(); });
  fileInput.addEventListener('change', function() {
    var file = fileInput.files[0];
    if (!file) return;
    addBubble('user', 'Bestand: ' + file.name);
    status.textContent = 'Bezig... (kan bij recepten of onderzoek een paar minuten duren)';
    postJson('/api/chat/upload', {
      method: 'POST',
      headers: {'X-Filename': encodeURIComponent(file.name)},
      body: file
    }).then(onReply).catch(onFail);
    fileInput.value = '';
  });

  if (navigator.mediaDevices && window.MediaRecorder) {
    var mediaRecorder = null;
    var chunks = [];
    var recording = false;
    micBtn.addEventListener('click', function() {
      if (!recording) {
        navigator.mediaDevices.getUserMedia({audio: true}).then(function(stream) {
          chunks = [];
          mediaRecorder = new MediaRecorder(stream);
          mediaRecorder.ondataavailable = function(e) { chunks.push(e.data); };
          mediaRecorder.onstop = function() {
            stream.getTracks().forEach(function(t) { t.stop(); });
            var blob = new Blob(chunks, {type: mediaRecorder.mimeType});
            status.textContent = 'Bezig met transcriberen...';
            postJson('/api/chat/voice', {method: 'POST', body: blob}).then(onReply).catch(onFail);
          };
          mediaRecorder.start();
          recording = true;
          micBtn.classList.add('recording');
          micBtn.title = 'Stop opname';
        }).catch(function(e) {
          addBubble('error', 'Microfoon niet beschikbaar: ' + e.message);
        });
      } else {
        mediaRecorder.stop();
        recording = false;
        micBtn.classList.remove('recording');
        micBtn.title = 'Inspreken';
      }
    });
  } else {
    micBtn.hidden = true;
  }
})();
</script>
"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def _send_html(self, body, status=200):
        encoded = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _send_json(self, obj, status=200):
        encoded = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        route = parsed.path
        params = urllib.parse.parse_qs(parsed.query)
        pages, todo, mtimes = get_cache()

        if route == "/":
            if not pages:
                self._send_html(render_page("Wiki", f"<p>Kan de wiki nu niet laden vanaf {html.escape(KENNISBANK_DIR)}. Probeer het later opnieuw.</p>"), status=503)
                return
            recent_paths = sorted(
                (p for p in pages if p != WIKI_ROOT),
                key=lambda p: mtimes.get(p, 0),
                reverse=True,
            )[:RECENT_COUNT]
            recent_items = "".join(
                f'<li><a href="/wiki/{wiki_path_to_route(p)}">{html.escape(extract_title(pages[p], wiki_path_to_route(p)))}</a></li>'
                for p in recent_paths
            )
            recent_html = (
                f"<h2>Recent toegevoegd</h2><ul>{recent_items}</ul>"
                if recent_items else "<p>Nog geen wiki-pagina's.</p>"
            )
            body = CHAT_HTML + render_search_form() + recent_html
            self._send_html(render_page("Wiki", body))
            return

        if route == "/todo":
            todo_html = markdown_to_html(todo, base_dir="docs/angie")
            self._send_html(render_page("Todo", todo_html))
            return

        if route == "/zoek":
            query = (params.get("q") or [""])[0].strip()
            results_html = ""
            if len(query) >= 2:
                ql = query.lower()
                hits = []
                for path, text in pages.items():
                    if path == WIKI_ROOT:
                        continue
                    if ql in text.lower():
                        plain = strip_markdown(text)
                        idx = plain.lower().find(ql)
                        start = max(0, idx - 60)
                        snippet = plain[start:idx + 100].strip()
                        title = extract_title(text, wiki_path_to_route(path))
                        hits.append((title, wiki_path_to_route(path), snippet))
                if hits:
                    items = "".join(
                        f'<div class="result"><a href="/wiki/{route_}">{html.escape(title)}</a>'
                        f'<div class="snippet">{html.escape(snippet)}</div></div>'
                        for title, route_, snippet in hits
                    )
                    results_html = items
                else:
                    results_html = f"<p>Niets gevonden voor &quot;{html.escape(query)}&quot;.</p>"
            body = render_search_form(query) + results_html
            self._send_html(render_page("Zoeken", body))
            return

        if route.startswith("/wiki/"):
            wiki_route = route[len("/wiki/"):]
            wiki_path = route_to_wiki_path(wiki_route)
            text = pages.get(wiki_path)
            if text is None:
                if wiki_route in CATEGORY_SLUGS:
                    title = wiki_route.capitalize()
                    self._send_html(render_page(title, f"<h1>{title}</h1><p>Nog geen pagina's in deze categorie.</p>"))
                    return
                self._send_html(render_page("Niet gevonden", "<p>Pagina niet gevonden.</p>"), status=404)
                return
            base_dir = os.path.dirname(wiki_path)
            content_html = markdown_to_html(text, base_dir=base_dir)
            title = extract_title(text, wiki_route)
            if wiki_path != WIKI_ROOT and wiki_route not in CATEGORY_SLUGS:
                content_html += render_page_actions(wiki_route, text)
            self._send_html(render_page(title, content_html))
            return

        self._send_html(render_page("Niet gevonden", "<p>Pagina niet gevonden.</p>"), status=404)

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        route = parsed.path
        length = int(self.headers.get("Content-Length", 0) or 0)
        raw_bytes = self.rfile.read(length) if length else b""

        if route == "/api/chat":
            try:
                payload = json.loads(raw_bytes.decode("utf-8")) if raw_bytes else {}
                text = (payload.get("text") or "").strip()
                if not text:
                    self._send_json({"error": "Leeg bericht."}, status=400)
                    return
                reply = call_n8n_cli(text)
                self._send_json({"reply": reply})
            except (urllib.error.URLError, OSError, TimeoutError) as e:
                self._send_json({"error": f"Angie is nu niet bereikbaar ({e})."}, status=502)
            except Exception as e:
                self._send_json({"error": f"Onverwachte fout: {e}"}, status=500)
            return

        if route == "/api/chat/voice":
            try:
                if not raw_bytes:
                    self._send_json({"error": "Geen audio ontvangen."}, status=400)
                    return
                transcript = call_whisper(raw_bytes)
                if not transcript:
                    self._send_json({"error": "Ik heb niets kunnen verstaan in dat spraakbericht."}, status=400)
                    return
                reply = call_n8n_cli(transcript)
                self._send_json({"transcript": transcript, "reply": reply})
            except (urllib.error.URLError, OSError, TimeoutError) as e:
                self._send_json({"error": f"Transcriberen of Angie niet bereikbaar ({e})."}, status=502)
            except Exception as e:
                self._send_json({"error": f"Onverwachte fout: {e}"}, status=500)
            return

        if route == "/api/chat/upload":
            try:
                # De bestandsnaam komt percent-encoded binnen (encodeURIComponent
                # in de browser): Safari op iOS gooit een TypeError zodra een
                # HTTP-headerwaarde niet-ASCII-tekens bevat (bijv. "Knäckebröd").
                filename = urllib.parse.unquote(self.headers.get("X-Filename", "bestand"))
                if not raw_bytes:
                    self._send_json({"error": "Geen bestand ontvangen."}, status=400)
                    return
                try:
                    text = extract_upload_text(raw_bytes, filename)
                except UploadDecodeError as e:
                    self._send_json({"error": html.escape(str(e))}, status=415)
                    return
                # Alleen een PDF heeft een origineel dat de moeite waard is om te
                # bewaren -- tekstextractie daarvan is lossy (opmaak/lay-out
                # gaat verloren). Bij .txt/.md is de geextraheerde tekst al
                # exact het origineel, dus daar is geen losse bijlage nodig.
                is_pdf = raw_bytes[:5] == b"%PDF-"
                bijlage = save_attachment(raw_bytes, filename) if is_pdf else None
                # Geen "Bestand ontvangen (filename):"-voorvoegsel meer: dat kwam
                # als eerste regel in de opgeslagen pagina terecht en werd dus de
                # titel/preview ("Bestand ontvangen (...): ...") in plaats van de
                # werkelijke inhoud. De bestandsnaam staat al in de bijlage-link.
                message = text[:4000]
                reply = call_n8n_cli(message, bijlage=bijlage)
                self._send_json({"reply": reply})
            except (urllib.error.URLError, OSError, TimeoutError) as e:
                self._send_json({"error": f"Angie is nu niet bereikbaar ({e})."}, status=502)
            except Exception as e:
                self._send_json({"error": f"Onverwachte fout: {e}"}, status=500)
            return

        raw_body = raw_bytes.decode("utf-8")
        params = urllib.parse.parse_qs(raw_body)

        if route == "/verwijder":
            wiki_route = (params.get("route") or [""])[0]
            wiki_path = route_to_wiki_path(wiki_route)
            pages, _todo, _mtimes = get_cache()
            if wiki_path == WIKI_ROOT or wiki_route in CATEGORY_SLUGS or wiki_path not in pages:
                self._send_html(render_page("Kan niet verwijderen", "<p>Deze pagina kan niet verwijderd worden.</p>"), status=400)
                return
            try:
                os.remove(local_wiki_path(wiki_path))
            except OSError as e:
                self._send_html(render_page("Verwijderen mislukt", f"<p>Verwijderen is niet gelukt: {html.escape(str(e))}. Mogelijk is de kennisbank-map read-only gemount.</p>"), status=500)
                return
            remove_links_to(pages, wiki_path)
            invalidate_cache()
            self.send_response(303)
            self.send_header("Location", "/")
            self.end_headers()
            return

        self._send_html(render_page("Niet gevonden", "<p>Pagina niet gevonden.</p>"), status=404)


def main():
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"Wiki-site draait op poort {PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
