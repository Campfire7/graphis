"""Testserver für das Laden der Modelle. Pfad /MODUS/REST liefert die Datei DATEN/REST.
ok: Range mit 206 oder 416, sonst 200. langsam: wie ok, aber gedrosselt. ohne-range: immer 200.
416: jede Range mit 416. falscher-bereich: Range mit 206 ab Byte 0. zu-gross: 200 mit Zusatzbytes. umleitung: 302 auf /ok/.
Jede Anfrage kommt als Zeile ins Protokoll: METHODE PFAD range=WERT STATUS."""
import os, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

DATEN = Path(sys.argv[1]); PROTOKOLL = Path(sys.argv[2]); PORTDATEI = Path(sys.argv[3])
schloss = threading.Lock()


class Bearbeiter(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *args):
        pass

    def notieren(self, status):
        with schloss, PROTOKOLL.open("a") as datei:
            datei.write(f"{self.command} {self.path} range={self.headers.get('Range', '-')} {status}\n")

    def antworten(self, status, kopf, inhalt=b"", langsam=False):
        self.notieren(status)
        self.send_response(status)
        for k, v in kopf.items():
            self.send_header(k, v)
        self.end_headers()
        try:
            if langsam:
                for i in range(0, len(inhalt), 32 * 1024):
                    self.wfile.write(inhalt[i:i + 32 * 1024]); self.wfile.flush(); time.sleep(0.03)
            else:
                self.wfile.write(inhalt)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        teile = self.path.lstrip("/").split("/", 1)
        if len(teile) != 2 or not (DATEN / teile[1]).is_file():
            return self.antworten(404, {"Content-Length": "0"})
        modus, rest = teile
        if modus == "umleitung":
            return self.antworten(302, {"Location": f"/ok/{rest}", "Content-Length": "0"})
        daten = (DATEN / rest).read_bytes()
        groesse = len(daten)
        bereich = self.headers.get("Range")
        art = {"Content-Type": "application/octet-stream"}
        if modus == "zu-gross":
            extra = daten + b"\0" * 1_000_000
            return self.antworten(200, {**art, "Content-Length": str(len(extra))}, extra)
        if bereich and modus == "416":
            return self.antworten(416, {"Content-Range": f"bytes */{groesse}", "Content-Length": "0"})
        if bereich and modus == "falscher-bereich":
            return self.antworten(206, {**art, "Content-Range": f"bytes 0-{groesse - 1}/{groesse}", "Content-Length": str(groesse)}, daten)
        if bereich and modus in ("ok", "langsam"):
            start = int(bereich.removeprefix("bytes=").split("-")[0])
            if start >= groesse:
                return self.antworten(416, {"Content-Range": f"bytes */{groesse}", "Content-Length": "0"})
            stueck = daten[start:]
            return self.antworten(206, {**art, "Content-Range": f"bytes {start}-{groesse - 1}/{groesse}",
                                        "Content-Length": str(len(stueck))}, stueck, langsam=modus == "langsam")
        return self.antworten(200, {**art, "Content-Length": str(groesse)}, daten, langsam=modus == "langsam")


server = ThreadingHTTPServer(("127.0.0.1", 0), Bearbeiter)
PORTDATEI.write_text(str(server.server_address[1]))
server.serve_forever()
