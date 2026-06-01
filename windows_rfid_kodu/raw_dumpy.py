import http.client

IP = "192.168.137.188"   # antenin guncel IP'si

def fetch():
    c = http.client.HTTPConnection(IP, 80, timeout=5)
    c.request("GET", "/")
    body = c.getresponse().read().decode("utf-8", errors="ignore")
    c.close()
    return body

input("1) Anteni BOS birak, Enter'a bas: ")
fetch()  # buffer'i temizle
input("   Bir kez daha Enter (asil olcum): ")
print("\n=== BOS ===")
print(repr(fetch()))

input("\n2) KART A'yi antenin uzerine koy, 3sn bekle, Enter: ")
print("\n=== KART A ===")
print(repr(fetch()))

input("\n3) KART B'yi antenin uzerine koy (A'yi cek), 3sn bekle, Enter: ")
print("\n=== KART B ===")
print(repr(fetch()))
