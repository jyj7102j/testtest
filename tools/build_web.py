"""Builds web/shop_simulator.html: the phone-playable web port with the game data
from assets/data/*.json inlined, so the web and Godot versions share one source
of numbers. Run after changing any data file:  python3 tools/build_web.py
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "assets" / "data"
TEMPLATE = ROOT / "web" / "shop_web_template.html"
OUTPUT = ROOT / "web" / "shop_simulator.html"
PLACEHOLDER = "/*__DATA__*/null"

FILES = {
    "shop_types": "shop_types.json",
    "customer_types": "customer_types.json",
    "upgrades": "shop_upgrades.json",
    "events": "market_events.json",
    "balance": "sim_balance.json",
}


def main() -> None:
    data = {key: json.loads((DATA_DIR / name).read_text(encoding="utf-8")) for key, name in FILES.items()}
    template = TEMPLATE.read_text(encoding="utf-8")
    if template.count(PLACEHOLDER) != 1:
        raise SystemExit(f"{TEMPLATE} must contain {PLACEHOLDER} exactly once")
    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    OUTPUT.write_text(template.replace(PLACEHOLDER, payload), encoding="utf-8")
    print(f"wrote {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
