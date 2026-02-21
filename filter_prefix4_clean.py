import csv

IN  = "data/canada_prefix4.csv"
OUT = "data/canada_prefix4_clean.csv"

keep = []
with open(IN, newline="", encoding="utf-8") as f:
    r = csv.DictReader(f)
    for row in r:
        brand = row["brand_guess"].strip()
        typ   = row["type_guess"].strip()
        issuer= row["issuer_guess"].strip()

        if brand in ("VISA","MASTERCARD","AMEX") and issuer != "Unknown" and typ != "unknown":
            keep.append(row)

# optional: limit to first 20
keep = keep[:20]

with open(OUT, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=r.fieldnames)
    w.writeheader()
    w.writerows(keep)

print(f"Wrote {len(keep)} rows -> {OUT}")