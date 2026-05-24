SearXNG blocking best practices (2026)

Summary:
- Prefer privacy-friendly engines and limit exposure of tracking engines (e.g., avoid Google/Bing for blocking risk). Use engine whitelisting to load only trusted engines.
- Enable rate limiting and bot defense to control abuse and reduce upstream blocks.
- Use per-engine proxies and outgoing proxy settings to circumvent rate-limiting blocks while maintaining anonymity.

Evidence references:
- Google/Bing/DuckDuckGo engines docs and engine whitelisting: https://github.com/searxng/searxng/blob/master/docs/dev/engines/online/google.rst and duckduckgo.rst; keep_only knob in settings.rst
- Rate limiter docs: https://github.com/searxng/searxng/blob/master/docs/admin/settings/settings_server.rst
- Proxy settings docs: https://github.com/searxng/searxng/blob/master/docs/admin/settings/settings_outgoing.rst and per-engine proxies: https://github.com/searxng/searxng/blob/master/docs/admin/settings/settings_engines.rst

Recommended configs (example snippets):

1) Block upstream by whitelisting engines (disable others)

use_default_settings: true
engines:
  - name: google
    engine: google
    shortcut: go
    categories: general
    safe_search: true
    weight: 1.0
    disabled: true
  - name: bing
    engine: bing
    shortcut: bi
    categories: general
    safe_search: true
    weight: 1.0
    disabled: true
  - name: duckduckgo
    engine: duckduckgo
    shortcut: ddg
    categories: general
    safe_search: true
    weight: 1.0
    disabled: false
  - name: wikipedia
    engine: wikipedia
    shortcut: wi
    categories: general
    safe_search: true
    weight: 1.0
    disabled: false
