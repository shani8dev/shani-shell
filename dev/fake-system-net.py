#!/usr/bin/env python3
"""Stands in for resolvectl, systemctl, ss, avahi-browse, caddy, cloudflared and
fail2ban-client (tests/test_system_net.py): fixed, realistic status output,
never a write to the machine. `fake-system-net.py fixtures` makes the config
fixtures in $FAKE_SYSTEM_NET; each tool call logs its argv to
$FAKE_SYSTEM_NET/calls. A token-looking file sits in the fake cloudflared
directory to catch a bridge that reads what it must only check for.

FAKE_SYSTEM_NET_F2B_REFUSE=1 answers fail2ban status with the daemon's socket
refusal (exit 255); FAKE_SYSTEM_NET_F2B_ABSENT=1 answers like a tool that is not
runnable. Every other argv is rejected with exit 2.
"""

import os, sys, time, traceback


def _logged(t, v, tb):  # a failure of the stand-in itself, for the part to show
    with open(
        os.path.join(os.environ.get("FAKE_SYSTEM_NET", "/tmp"), "errors"), "a"
    ) as f:
        f.write("".join(traceback.format_exception(t, v, tb)))


sys.excepthook = _logged

D = os.environ["FAKE_SYSTEM_NET"]
os.makedirs(D, exist_ok=True)
open(os.path.join(D, "calls"), "a").write(
    os.path.basename(sys.argv[0]) + " " + " ".join(sys.argv[1:]) + "\n"
)

FILES = {
    "resolv.conf.real": "# Fixture: the file the symlink points at\n"
    "nameserver 127.0.0.53\n"
    "search lan home\n",
    "Caddyfile": "# Fixture with a secret a reader must never print\n"
    "example.com {\n"
    '    respond "hello"\n'
    "    header X-Api-Token super-secret-value-123\n"
    "}\n"
    "\n"
    "localhost:8080 {\n"
    "    reverse_proxy 127.0.0.1:9000\n"
    "}\n",
    "ip_forward": "1\n",
    "exim.conf": ".ifdef ROUTER_SMARTHOST\n"
    "smart_route:\n"
    "  driver = manualroute\n"
    "  domains = ! +local_domains\n"
    "  route_list = * smtp.example.com\n"
    "  no_more\n"
    ".endif\n",
    "exim-direct.conf": "# No ROUTER_SMARTHOST here\n"
    "dnslookup:\n"
    "  driver = dnslookup\n",
    "exim-bad.conf": ".ifdef ROUTER_SMARTHOST\n"
    "smart_route:\n"
    "  route_list = * user:secret@smtp.example.com\n"
    ".endif\n",
    "cloudflared-config/config.yml": "tunnel: home\ncredentials-file: /etc/cloudflared/home.json\n",
    "cloudflared-config/token.json": '{"token": "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJzZWNyZXQifQ.signature"}',
}


def fixtures():
    for name, text in FILES.items():
        p = os.path.join(D, name)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        if not os.path.exists(p):
            with open(p, "w") as f:
                f.write(text)
    link = os.path.join(D, "resolv.conf")
    if not os.path.islink(link) and not os.path.exists(link):
        os.symlink("resolv.conf.real", link)


prog = os.path.basename(sys.argv[0])
a = sys.argv[1:]
if prog == "fake-system-net.py" and a[:1] == ["fixtures"]:
    fixtures()
    sys.exit(0)
fixtures()

if prog == "resolvectl":
    print("""Global
           Protocols: -LLMNR +mDNS -DNSOverTLS DNSSEC=no/unsupported
    resolv.conf mode: stub
  Current DNS Server: 1.1.1.1
         DNS Servers: 1.1.1.1 8.8.8.8
          DNS Domain: home

Link 2 (enp1s0)
Current Scopes: DNS
     DNS Servers: 192.168.1.1

Link 3 (wlan0)
Current Scopes: DNS
     DNS Servers: 1.1.1.1""")
elif prog.startswith("systemctl"):
    if a[:1] == ["is-active"]:
        print(
            "active"
            if a[-1]
            in ("systemd-resolved", "sshd", "sshd.service", "avahi-daemon.service")
            else "inactive"
        )
    else:
        sys.exit(1)
elif prog == "ss":
    print("""State    Recv-Q  Send-Q  Local Address:Port   Peer Address:Port  Process
LISTEN   0       128          0.0.0.0:22        0.0.0.0:*      users:(("sshd",pid=742,fd=3))
LISTEN   0       4096            [::]:443          [::]:*      users:(("caddy",pid=910,fd=8))
LISTEN   0       128          127.0.0.1:631      0.0.0.0:*      users:(("cupsd",pid=611,fd=10))""")
elif prog == "avahi-browse":
    if os.path.exists(os.path.join(D, "hang-avahi")):
        time.sleep(30)
    print("""+;wlan0;IPv4;Living Room Printer;_ipp._tcp;local;living-room.local;192.168.1.42;631;
+;wlan0;IPv4;Sharing Box;_smb._tcp;local;sharing-box.local;192.168.1.50;445;
-;wlan0;IPv4;Cached Box;_ssh._tcp;local;cached.local;192.168.1.60;22;""")
elif prog == "caddy":
    if a[:1] == ["validate"]:
        config = a[a.index("--config") + 1] if "--config" in a else ""
        if not os.path.isfile(config):
            sys.exit(1)
        print("Valid configuration")
    else:
        sys.exit(2)
elif prog == "cloudflared":
    if a[:2] == ["tunnel", "list"]:
        print("""ID                                   NAME        CREATED
6f1a2b3c-4d5e-6f70-8192-a3b4c5d6e7f8  home        2025-01-02
9c8b7a65-4321-4fed-8000-1234567890ab  workshop    2025-03-14""")
    else:
        sys.exit(2)
elif prog == "fail2ban-client":
    if os.environ.get("FAKE_SYSTEM_NET_F2B_ABSENT") == "1":
        sys.stderr.write("fail2ban-client: command not found\n")
        sys.exit(127)
    if os.environ.get("FAKE_SYSTEM_NET_F2B_REFUSE") == "1":
        print(
            "ERROR   Permission denied to socket: "
            "/var/run/fail2ban/fail2ban.sock, (you must be root)"
        )
        sys.exit(255)
    if a == ["status"]:
        print("Status\n|- Number of jail:\t1\n`- Jail list:\tsshd")
    elif a == ["status", "sshd"]:
        print(
            "Status for the jail: sshd\n"
            "|- Filter\n"
            "|  |- Currently failed:\t0\n"
            "|  |- Total failed:\t0\n"
            "|  `- Journal matches:\t_SYSTEMD_UNIT=sshd.service + _COMM=sshd\n"
            "`- Actions\n"
            "   |- Currently banned:\t2\n"
            "   |- Total banned:\t7\n"
            "   `- Banned IP list:\t192.0.2.44 198.51.100.7"
        )
    else:
        sys.exit(2)
else:
    sys.exit(2)
