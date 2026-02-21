import json, re, csv, sys

IN_PATH  = sys.argv[1] if len(sys.argv) > 1 else "data/bins_raw.json"
OUT_6    = sys.argv[2] if len(sys.argv) > 2 else "data/canada_iin6.csv"
OUT_4    = sys.argv[3] if len(sys.argv) > 3 else "data/canada_prefix4.csv"

# Hackathon knob: if a row looks like a bank card but no type keywords exist,
# assume "credit" instead of "unknown".
ASSUME_CREDIT_IF_UNCLEAR = True

# Canonical issuer names for matching
ISSUER_MAP = {
    "rbc": "RBC",
    "royal bank of canada": "RBC",
    "td canada trust": "TD",
    "tdcanada": "TD",
    "td bank": "TD",
    "scotiabank": "Scotiabank",
    "bank of nova scotia": "Scotiabank",
    "bmo": "BMO",
    "bank of montreal": "BMO",
    "cibc": "CIBC",
    "canadian imperial bank of commerce": "CIBC",
    "mbna": "MBNA",
    "national bank of canada": "National Bank",
    "national bank": "National Bank",
    "desjardins": "Desjardins",
    "vancity": "Vancity",
    "tangerine": "Tangerine",
    "simplii": "Simplii",
    "meridian": "Meridian",
    "peoples trust": "Peoples Trust",
    "canada post": "Canada Post",
    "president's choice": "PC Financial",
    "pc financial": "PC Financial",
    "canadian tire": "Canadian Tire",
    "husky": "Husky/Mohawk",
    "mohawk": "Husky/Mohawk",
    "ing direct canada": "ING Direct Canada",
    "hsbc bank canada": "HSBC Canada",
    "hsbc canada": "HSBC Canada",
    "laurentian": "Laurentian",
    "banque laurentienne": "Laurentian",
}

# If a description explicitly mentions a non-Canada country marker, drop it.
# (Keeps CA/Canada markers.)
NON_CA_MARKERS = [
    "(uk)", "(italy)", "(it)", "(spain)", "(es)", "(poland)", "(pl)", "(usa)", "(us)", "(france)", "(fr)",
    "(germany)", "(de)", "(australia)", "(au)", "(new zealand)", "(nz)", "(sweden)", "(se)", "(singapore)", "(sg)",
    "(hong kong)", "(hk)", "(mexico)", "(mx)", "(peru)", "(pe)", "(venezuela)", "(ve)", "(hungary)", "(hu)",
    "(estonia)", "(ee)", "(russia)", "(ru)", "(china)", "(cn)", "(japan)", "(jp)", "(korea)", "(kr)"
]
NON_CA_TEXT = [" - uk", ", uk", " - italy", ", italy", " - spain", ", spain", " - usa", ", usa"]

def normalize_key(k: str) -> str:
    return re.sub(r"\D", "", k)

def guess_brand(prefix: str) -> str:
    if prefix.startswith(("34", "37")): return "AMEX"
    if prefix.startswith("4"): return "VISA"
    if prefix.startswith("5"): return "MASTERCARD"
    return "OTHER"

def guess_type(desc: str) -> str:
    s = desc.lower()
    # prepaid/gift first
    if any(w in s for w in ["prepaid", "gift", "reloadable", "vanilla", "stored value"]):
        return "prepaid"
    # debit next
    if any(w in s for w in ["debit", "atm", "interac", "electron", "check card"]):
        return "debit"
    # credit signals (includes common tiers that imply credit)
    if any(w in s for w in ["credit", "platinum", "gold", "infinite", "world", "world elite", "signature"]):
        return "credit"
    return "unknown"

def issuer_guess(desc: str) -> str:
    s = desc.lower()
    for k, v in ISSUER_MAP.items():
        if k in s:
            return v
    return "Unknown"

def is_canada_strict(desc: str) -> bool:
    s = desc.lower().strip()
    # whole word "canada"
    if re.search(r"\bcanada\b", s):
        return True
    # explicit (CA)
    if re.search(r"\(ca\)", s):
        return True
    # dataset format: "CA     Bank of Montreal ..."
    if re.match(r"^ca\s", s):
        return True
    return False

def has_explicit_non_ca(desc: str) -> bool:
    s = desc.lower()
    if any(m in s for m in NON_CA_MARKERS):
        return True
    if any(m in s for m in NON_CA_TEXT):
        return True
    return False

with open(IN_PATH, "r", encoding="utf-8") as f:
    data = json.load(f)

rows6, rows4 = [], []

for k, v in data.items():
    if not isinstance(k, str) or not isinstance(v, str):
        continue

    key = normalize_key(k)
    desc = v.strip()

    # Keep only 4 or 6 digit keys
    if len(key) not in (4, 6):
        continue

    # Canada filter: must be Canada-marked OR match a known Canadian issuer keyword
    # and must NOT contain explicit non-CA markers.
    iss = issuer_guess(desc)
    if not (is_canada_strict(desc) or iss != "Unknown"):
        continue
    if has_explicit_non_ca(desc):
        continue

    brand = guess_brand(key)
    typ = guess_type(desc)
    if typ == "unknown" and ASSUME_CREDIT_IF_UNCLEAR and iss != "Unknown" and brand in ("VISA", "MASTERCARD", "AMEX"):
        typ = "credit"  # hackathon-friendly default

    out = {
        "key": key,
        "brand_guess": brand,
        "type_guess": typ,
        "issuer_guess": iss,
        "desc": desc
    }

    if len(key) == 6:
        rows6.append(out)
    else:
        rows4.append(out)

rows6.sort(key=lambda r: r["key"])
rows4.sort(key=lambda r: r["key"])

with open(OUT_6, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=["key", "brand_guess", "type_guess", "issuer_guess", "desc"])
    w.writeheader()
    w.writerows(rows6)

with open(OUT_4, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=["key", "brand_guess", "type_guess", "issuer_guess", "desc"])
    w.writeheader()
    w.writerows(rows4)

print(f"Wrote {len(rows6)} rows -> {OUT_6}")
print(f"Wrote {len(rows4)} rows -> {OUT_4}")