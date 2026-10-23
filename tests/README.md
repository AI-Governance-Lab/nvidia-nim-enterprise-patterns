# Ghid de Testare - NVIDIA NIM (OpenAI Compatible API)

Acest director conține scripturi și documentație pentru testarea oricărui model LLM găzduit prin **NVIDIA NIM** (sau orice alt server compatibil cu formatul OpenAI, precum vLLM, Ollama, TGI etc.).

## Conținut
- `test_nim_api.py` - Un script Python inteligent care detectează automat modelul încărcat și testează conectivitatea și calitatea răspunsurilor.

## Cerințe preliminare (Prerequisites)
Pentru a rula scriptul de test, ai nevoie de biblioteca `requests`:
```bash
pip3 install requests
```

## Cum funcționează scriptul de test?
Scriptul a fost conceput pentru a fi **100% agnostic față de model**. 
1. Când este apelat, prima acțiune este să acceseze `http://<HOST>:<PORT>/v1/models`.
2. Citește și afișează lista de modele active găsite pe acel server.
3. Dacă nu specifici tu un model, **îl selectează automat pe primul din listă**.
4. Trimite un set de prompturi de test (logică, programare, cunoștințe generale) pentru a verifica capabilitățile.

---

## 🚀 Utilizare

### 1. Testare de pe aceeași mașină (Local)
Dacă te afli în terminalul mașinii virtuale pe care rulează NIM:
```bash
python3 test_nim_api.py
```
*(În mod implicit, va accesa `localhost` pe portul `8000`)*

### 2. Testare din exterior (Laptop, alt VM, etc.)
Deoarece IP-ul extern al mașinii virtuale din Cloud este adesea **dinamic** (se schimbă la restart), trebuie mai întâi să afli IP-ul public curent:
- Rulând pe VM: `curl ifconfig.me`
- Sau verificând interfața (GCP / AWS / Azure).

După ce ai IP-ul, folosește parametrul `--host`:
```bash
python3 test_nim_api.py --host <VM_PUBLIC_IP>
```

### 3. Argumente și Opțiuni Avansate
Scriptul acceptă argumente pentru a fi perfect adaptabil:

- `--host`: Adresa IP sau domeniul (ex: `203.0.113.50` sau `api.example.com`)
- `--port`: Portul (Default: `8000`)
- `--model`: ID-ul specific al unui model (dacă ai mai multe încărcate și vrei să testezi unul anume).
- `--prompt`: Un prompt personalizat. Dacă îl folosești, scriptul nu va mai rula suita de teste predefinită, ci va răspunde doar la ce ai cerut tu.

**Exemplu complex:**
```bash
python3 test_nim_api.py --host <VM_PUBLIC_IP> --port 8000 --model "deepseek-ai/deepseek-r1" --prompt "Explică-mi teoria relativității pe scurt."
```

## Troubleshooting
- **`Connection Timeout` / Eroare de conexiune la host extern:** Verifică IP-ul mașinii și asigură-te că regula de Firewall din Cloud permite accesul pe portul folosit (ex. `8000`) pentru IP-ul tău sursă sau `0.0.0.0/0`.
- **Eroare `404 Not Found`:** Verifică dacă containerul NIM a pornit complet. Generarea motorului TensorRT-LLM la pornire poate dura de la câteva secunde la câteva minute, timp în care API-ul nu răspunde complet.
