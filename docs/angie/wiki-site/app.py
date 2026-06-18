#!/usr/bin/env python3
"""Niet-publieke wiki-site voor de kennisbank.

Leest alles rechtstreeks van de lokale schijf: kennisbank/wiki/*.md (staat
alleen op deze Pi, nooit op GitHub) en TODO.md (een lokale kopie naast
app.py, ververst met refresh-todo.sh wanneer nodig). Geen netwerkverkeer
meer terwijl de site draait — werkt ook zonder internetverbinding. Bouwt
de paginastructuur door vanuit wiki/index.md de markdown-links te volgen
(dezelfde regel als de "geen wees-pagina's"-controle in
kennisbank/Claude.md), en serveert dat als mobielvriendelijke HTML met een
zoekfunctie. Geen database, geen externe packages: alleen de Python-
standaardbibliotheek.

Bedoeld om uitsluitend bereikbaar te zijn via `tailscale serve` (tailnet-
only), nooit via `tailscale funnel` (publiek internet).
"""
import html
import os
import re
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

KENNISBANK_DIR = os.environ.get("KENNISBANK_DIR", os.path.expanduser("~/kennisbank"))
WIKI_ROOT = "kennisbank/wiki/index.md"
TODO_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "TODO.md")
PORT = 8090
CACHE_TTL = 300  # seconden

_cache_lock = threading.Lock()
_cache = {"pages": {}, "todo": "", "built_at": 0.0}


def fetch_local_todo():
    """Leest de lokale TODO.md-kopie naast app.py (nooit GitHub)."""
    try:
        with open(TODO_PATH, "r", encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def fetch_local_wiki(path):
    """Leest een kennisbank/wiki/*.md-pad van de lokale schijf (nooit GitHub)."""
    rel = path[len("kennisbank/"):]
    full = os.path.join(KENNISBANK_DIR, rel)
    try:
        with open(full, "r", encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


def crawl_wiki():
    """Volgt links vanuit wiki/index.md om alle wiki-pagina's te vinden."""
    pages = {}
    seen = set()
    queue = [WIKI_ROOT]
    while queue:
        path = queue.pop(0)
        if path in seen:
            continue
        seen.add(path)
        text = fetch_local_wiki(path)
        if text is None:
            continue
        pages[path] = text
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
    return pages


def get_cache():
    with _cache_lock:
        if time.time() - _cache["built_at"] > CACHE_TTL:
            pages = crawl_wiki()
            todo = fetch_local_todo() or "_TODO.md kon niet geladen worden._"
            if pages:
                _cache["pages"] = pages
                _cache["todo"] = todo
                _cache["built_at"] = time.time()
        return _cache["pages"], _cache["todo"]


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
  .top-nav {{ display: flex; gap: 1rem; margin-bottom: 1rem; font-size: 0.95rem; }}
  .todo-box {{
    background: #fff7e0; border: 1px solid #e8d28a; border-radius: 10px;
    padding: 0.8rem 1rem; margin-bottom: 1.5rem;
  }}
  @media (prefers-color-scheme: dark) {{
    .todo-box {{ background: #2a2410; border-color: #6b5a1e; }}
  }}
  .todo-box h1, .todo-box h2 {{ margin-top: 0.3rem; font-size: 1.05rem; }}
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
</style>
</head>
<body>
<div class="top-nav"><a href="/">Wiki</a> · <a href="/#todo">Todo</a></div>
{body}
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

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        route = parsed.path
        params = urllib.parse.parse_qs(parsed.query)
        pages, todo = get_cache()

        if route == "/":
            if not pages:
                self._send_html(render_page("Wiki", f"<p>Kan de wiki nu niet laden vanaf {html.escape(KENNISBANK_DIR)}. Probeer het later opnieuw.</p>"), status=503)
                return
            todo_html = markdown_to_html(todo, base_dir="docs/angie")
            index_path = WIKI_ROOT
            index_html = markdown_to_html(pages.get(index_path, ""), base_dir="kennisbank/wiki")
            body = (
                f'<div class="todo-box" id="todo"><h2>Todo</h2>{todo_html}</div>'
                f"{render_search_form()}"
                f"{index_html}"
            )
            self._send_html(render_page("Wiki", body))
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
                        title_match = re.search(r"^#\s+(.*)$", text, re.MULTILINE)
                        title = title_match.group(1) if title_match else wiki_path_to_route(path)
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
                self._send_html(render_page("Niet gevonden", "<p>Pagina niet gevonden.</p>"), status=404)
                return
            base_dir = os.path.dirname(wiki_path)
            content_html = markdown_to_html(text, base_dir=base_dir)
            title_match = re.search(r"^#\s+(.*)$", text, re.MULTILINE)
            title = title_match.group(1) if title_match else wiki_route
            self._send_html(render_page(title, content_html))
            return

        self._send_html(render_page("Niet gevonden", "<p>Pagina niet gevonden.</p>"), status=404)


def main():
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"Wiki-site draait op poort {PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
