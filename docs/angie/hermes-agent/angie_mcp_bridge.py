#!/usr/bin/env python3
"""MCP-stdio-server die Hermes Agent (op de Mac Mini) laat communiceren met
de Project Angie wiki-assistent via de bestaande n8n-webhook
(/webhook/angie-cli op de Raspberry Pi).

Vereist: pip install mcp
Vereist env var: ANGIE_WEBHOOK_URL (volledige URL inclusief /webhook/angie-cli,
bv. https://<jouw-tailscale-naam>.ts.net/webhook/angie-cli)

Registratie in ~/.hermes/cli-config.yaml:

mcp_servers:
  angie-wiki:
    command: python3
    args: ["/pad/naar/angie_mcp_bridge.py"]
    env:
      ANGIE_WEBHOOK_URL: "https://<jouw-tailscale-naam>.ts.net/webhook/angie-cli"
"""
import json
import os
import sys
import urllib.error
import urllib.request

from mcp.server.fastmcp import FastMCP

WEBHOOK_URL = os.environ.get("ANGIE_WEBHOOK_URL", "").strip()
if not WEBHOOK_URL:
    print("FOUT: ANGIE_WEBHOOK_URL is niet gezet -- zie env-blok in cli-config.yaml.", file=sys.stderr)
    sys.exit(1)

mcp = FastMCP("angie-wiki")


@mcp.tool()
def angie_command(text: str) -> str:
    """Stuur tekst of een /commando naar de Project Angie wiki-assistent (n8n) en
    geef het antwoord terug. Gebruik dit voor alles wat met de persoonlijke wiki
    of kennisbank te maken heeft: notities opslaan, taken, recepten, dagboek,
    administratie/facturen/bonnen, wiki-vragen, onderzoek, braindumps, etc.
    Voorbeelden: '/taken', '/wiki wat staat er over X', '/notitie ...',
    of gewone tekst (bv. een factuur of een idee) zonder commando -- de
    assistent bepaalt dan zelf de juiste actie.
    """
    body = json.dumps({"text": text}).encode("utf-8")
    req = urllib.request.Request(
        WEBHOOK_URL, data=body,
        headers={"Content-Type": "application/json"}, method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.URLError as e:
        return f"Kon de Angie-webhook niet bereiken ({e}). Draait n8n, en is de Tailscale-funnel actief?"
    except json.JSONDecodeError:
        return "Onverwacht antwoord (geen geldige JSON) van de Angie-webhook."
    return data.get("reply") or json.dumps(data, ensure_ascii=False)


if __name__ == "__main__":
    mcp.run()
