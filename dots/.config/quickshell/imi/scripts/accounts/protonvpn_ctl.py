#!/usr/bin/env python3
"""Proton VPN through the official app's session (python-proton-vpn-api-core).

  protonvpn_ctl.py status               -> {"installed", "logged_in", "state", "server", "country", "account"}
  protonvpn_ctl.py connect [COUNTRY]    -> connects to the fastest server (in COUNTRY, ISO code) and waits
  protonvpn_ctl.py disconnect
  protonvpn_ctl.py countries            -> {"countries": [{"code", "name"}]}

The shell never sees the Proton password: the session is the one the
proton-vpn-gtk-app stored in the keyring. Without the package `installed` is
false; without a login `logged_in` is false. Always prints one JSON object.
"""
import asyncio
import json
import sys

try:
    from proton.vpn.core.api import ProtonVPNAPI
    from proton.vpn.core.session_holder import ClientTypeMetadata
    INSTALLED = True
except Exception:  # noqa: BLE001 - any import failure means "not installed"
    INSTALLED = False


def out(obj, code=0):
    print(json.dumps(obj))
    sys.exit(code)


def state_name(state):
    return type(state).__name__ if state is not None else ""


def details(connector):
    conn = connector.current_connection
    server = getattr(conn, "server_name", "") if conn else ""
    country = ""
    try:
        country = conn._vpnserver.server_name.split("#")[0][:2] if conn else ""  # noqa: SLF001
    except Exception:  # noqa: BLE001
        country = ""
    return server or "", country


async def with_api(fn):
    api = ProtonVPNAPI(ClientTypeMetadata(type="cli"))
    if not api.is_user_logged_in():
        out({"installed": True, "logged_in": False, "state": "", "server": "", "country": "", "account": ""})
    connector = await api.get_vpn_connector()
    return await fn(api, connector)


async def do_status(api, connector):
    server, country = details(connector)
    out({"installed": True, "logged_in": True, "state": state_name(connector.current_state),
         "server": server, "country": country, "account": api.account_name or ""})


async def wait_for(connector, wanted, timeout=45.0):
    loop = asyncio.get_event_loop()
    deadline = loop.time() + timeout
    while loop.time() < deadline:
        name = state_name(connector.current_state)
        if name in wanted or name == "Error":
            return name
        await asyncio.sleep(0.3)
    return state_name(connector.current_state)


async def do_connect(api, connector, country):
    await api.refresher.enable()
    servers = api.server_list
    server = servers.get_fastest_in_country(country.upper()) if country else servers.get_fastest()
    vpn_server = connector.get_vpn_server(server, api.refresher.client_config)
    await connector.connect(vpn_server)
    name = await wait_for(connector, ("Connected",))
    await api.refresher.disable()
    srv, ctry = details(connector)
    out({"ok": name == "Connected", "state": name, "server": srv or server.name, "country": ctry or server.exit_country},
        0 if name == "Connected" else 1)


async def do_disconnect(api, connector):
    await connector.disconnect()
    name = await wait_for(connector, ("Disconnected",))
    out({"ok": name == "Disconnected", "state": name}, 0 if name == "Disconnected" else 1)


async def do_countries(api, connector):
    await api.refresher.enable()
    seen = {}
    for s in api.server_list:
        code = s.exit_country
        if code and code not in seen:
            seen[code] = s.exit_country_name
    await api.refresher.disable()
    out({"countries": [{"code": c, "name": n} for c, n in sorted(seen.items(), key=lambda kv: kv[1])]})


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "status"
    if not INSTALLED:
        out({"installed": False, "logged_in": False, "state": "", "server": "", "country": "", "account": ""})
    try:
        if cmd == "status":
            asyncio.run(with_api(do_status))
        elif cmd == "connect":
            country = argv[2] if len(argv) > 2 else ""
            asyncio.run(with_api(lambda a, c: do_connect(a, c, country)))
        elif cmd == "disconnect":
            asyncio.run(with_api(do_disconnect))
        elif cmd == "countries":
            asyncio.run(with_api(do_countries))
        else:
            out({"error": "usage: status|connect [COUNTRY]|disconnect|countries"}, 2)
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001 - one JSON line, always
        out({"error": f"{type(e).__name__}: {e}"}, 1)


if __name__ == "__main__":
    main(sys.argv)
