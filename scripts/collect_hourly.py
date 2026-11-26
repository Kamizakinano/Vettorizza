"""Salva ogni ora i totali pubblici di un profilo MakerWorld (per gli "Orari migliori")."""
import json, sys, time, urllib.request, os

UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Safari/537.36"}

def get(url):
    for i in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
                return json.load(r)
        except Exception as e:
            err = e; time.sleep(5)
    raise err

def collect(uid):
    p = get(f"https://makerworld.com/api/v1/user-service/user/profile/{uid}")
    dl = pr = lk = co = 0; off = 0
    while True:
        page = get(f"https://makerworld.com/api/v1/design-service/published/{uid}/design?offset={off}&limit=50")
        hits = page.get("hits") or []
        for h in hits:
            dl += h.get("downloadCount", 0); pr += h.get("printCount", 0)
            lk += h.get("likeCount", 0); co += h.get("collectionCount", 0)
        off += len(hits)
        if not hits or off >= page.get("total", 0): break
    return {"t": int(time.time()), "d": dl, "p": pr, "l": lk, "c": co, "f": p.get("fanCount", 0)}

if __name__ == "__main__":
    name, uid, out = sys.argv[1], sys.argv[2], sys.argv[3]
    s = collect(uid)
    data = {"handle": name, "samples": []}
    if os.path.exists(out):
        data = json.load(open(out))
    data["samples"] = [x for x in data["samples"] if x["t"] > s["t"] - 120 * 86400][-5000:] + [s]
    os.makedirs(os.path.dirname(out), exist_ok=True)
    json.dump(data, open(out, "w"), separators=(",", ":"))
    print(s)
