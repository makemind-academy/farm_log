#!/usr/bin/env python3
"""farm-log: the average days to first flower is computed from the records and appears nowhere in the source."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "tools"))
from appplayer import AppPlayer  # noqa: E402
from mcpclient import Server  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.join(HERE, "farm_server")
CAP = os.path.join(HERE, "captures")
SERVER_ID = "com.makemind.sample.farm_log"

with Server(["dart", "run", "bin/server.dart"], cwd=SERVER) as s:
    before = s.call("log.season", {"crop": "Tomato"})
    assert before["seasonCount"] == 1
    cmp = s.call("log.compare", {"crop": "Tomato"})
    assert cmp["spanCount"] >= 5 and 15 < float(cmp["avgDays"]) < 25, cmp
    src = open(os.path.join(SERVER, "bin", "server.dart")).read()
    assert str(cmp["avgDays"]) not in src, "the average must come from the records, not the source"

ap = AppPlayer()
ap.register_server(SERVER_ID, "Farm log", cwd=SERVER)
ap.restart()
ap.open_server(SERVER_ID)
ap.wait_text("This season")
ap.shot(f"{CAP}/01_today.png")
ap.tap("Log: watered")
ap.wait_text("watered recorded")
dates = [t for t, _ in ap.texts("2026-") if len(t) == 10]
assert len(dates) == 2, f"the entry logged from the screen is not in the list: {dates}"
ap.shot(f"{CAP}/02_after_one_tap.png")
ap.tap("Compare seasons →")
ap.wait_text("first flower")
ap.expect_aligned(" d", min_rows=5)
ap.shot(f"{CAP}/03_seasons_compared.png")
print("farm-log: an entry logged from the screen, seasons compared, the average computed from records")
