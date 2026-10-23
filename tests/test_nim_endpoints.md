# Ghid de Testare Endpoints NIM (Local și Extern)

Acest document conține comenzile necesare pentru a verifica funcționarea API-ului NVIDIA Inference Microservice (NIM) cu modelul DeepSeek R1, atât din interiorul mașinii virtuale (VM), cât și din exterior, folosind IP-ul public.

## 1. Verificarea Locală (pe VM)

Aceste comenzi se rulează direct în terminalul VM-ului pe care rulează containerul NIM.

### A. Listarea modelelor disponibile
Pentru a verifica dacă serverul răspunde și pentru a obține ID-ul exact al modelului încărcat:
```bash
curl http://localhost:8000/v1/models
```
*Vei obține un răspuns JSON. Caută valoarea câmpului `"id"` (ex: `deepseek-ai/deepseek-r1-distill-llama-8b`).*

### B. Testarea generării de text (Localhost)
Folosește ID-ul obținut mai sus pentru a trimite un prompt:
```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-ai/deepseek-r1-distill-llama-8b",
    "messages": [
      {
        "role": "user",
        "content": "Salut! Ce imi poti spune despre tine in 2 fraze?"
      }
    ],
    "max_tokens": 200,
    "temperature": 0.6
  }'
```

---

## 2. Verificarea Externă (de pe laptop/remote)

Conform configurației de infrastructură (Terraform), portul `8000` este expus extern prin firewall. Pentru a folosi API-ul din afara VM-ului, trebuie să afli IP-ul public și să rulezi cererile către acesta.

### A. Aflarea IP-ului public (Rulează pe VM)
Pentru a afla rapid ce IP public are VM-ul tău:
```bash
export PUBLIC_IP=$(curl -s ifconfig.me)
echo "IP-ul extern este: $PUBLIC_IP"
```

### B. Testarea generării de text din interiorul VM-ului folosind IP-ul Extern
Folosind variabila de mediu setată anterior, testează dacă serverul acceptă conexiuni prin interfața externă:
```bash
curl -X POST http://$PUBLIC_IP:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-ai/deepseek-r1-distill-llama-8b",
    "messages": [
      {
        "role": "user",
        "content": "Salut! Testez conexiunea prin IP-ul public expus."
      }
    ],
    "max_tokens": 100
  }'
```

### C. Testarea generării de text de pe laptop (Remote)
Înlocuiește `<IP_PUBLIC>` cu IP-ul aflat la pasul anterior și rulează comanda în terminalul laptopului tău:
```bash
curl -X POST http://<IP_PUBLIC>:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-ai/deepseek-r1-distill-llama-8b",
    "messages": [
      {
        "role": "user",
        "content": "Salut! Acesta este un test de la distanta prin IP-ul extern."
      }
    ],
    "max_tokens": 100
  }'
```

## Troubleshooting (Port Forwarding)
Dacă testul extern eșuează (ex. `Connection refused` sau timeout), deși portul `8000` este deschis în Firewall:
- Asigură-te că NIM a fost pornit în Docker mapând portul pe toate interfețele: `-p 8000:8000` sau `-p 0.0.0.0:8000:8000`. Dacă ai folosit `-p 127.0.0.1:8000:8000`, API-ul va accepta cereri doar de la procese ce rulează pe același VM.

---

## 3. Sfaturi și verificări specifice pentru DeepSeek R1

DeepSeek R1 este un model axat pe "reasoning" (raționament pas cu pas), ceea ce înseamnă că interacțiunea cu el este puțin diferită de a altor modele LLM clasice (precum GPT-4 sau Llama obișnuit). Pe viitor, fii atent la următoarele aspecte:

### A. Formatul răspunsului: tag-urile `<think>`
Când soliciți rezolvarea unei probleme logice sau de codare, DeepSeek R1 (și variantele distill) va genera mai întâi propriul lanț de raționament intern.
- Acest raționament este înconjurat de tag-urile `<think> ... </think>` și va apărea direct în conținutul răspunsului primit de la API (`choices[0].message.content`).
- **De verificat:** Dacă folosești acest API într-o aplicație UI, asigură-te că aplicația filtrează sau ascunde textul dintre aceste tag-uri pentru a nu confunda utilizatorul final (sau îl afișează într-un bloc stilizat separat, gen "Gândire:").

### B. Evită Prompturile de Sistem Complexe (System Prompts)
La DeepSeek R1 este recomandat (ca best-practice) să îi dai modelului problema direct ca mesaj de tip `user`.
- **Nu** îi spune în promptul de sistem "Gândește pas cu pas" (Think step by step), deoarece el face automat acest lucru. Un prompt de sistem prea restrictiv îi poate strica "fluxul" de raționament încorporat.

### C. Consumul mai mare de timp și VRAM (Pe GPU-ul L4)
Deoarece modelele de reasoning generează zeci sau sute de "tokeni de gândire" invizibili (CoT - Chain of Thought) pe lângă răspunsul final, o interogare:
- Va dura mai mult până începe să livreze răspunsul util.
- Va ocupa temporar mai mult VRAM pe L4.
- **De verificat:** Rulează în background comanda `watch -n 1 nvidia-smi` în timpul unui test complex de raționament pentru a te asigura că nu depășești capacitatea memoriei GPU-ului L4 (24GB).

### D. Comandă de test pentru capacitatea de reasoning
Pentru a verifica dacă mecanismul de gândire (`<think>`) se declanșează și funcționează optim, rulează acest test de deducție logică:

```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-ai/deepseek-r1-distill-llama-8b",
    "messages": [
      {
        "role": "user",
        "content": "Avem 3 cutii etichetate: doar mere, doar portocale, respectiv mere si portocale. Toate cele 3 etichete sunt gresite. Ai voie sa scoti un singur fruct dintr-o singura cutie. Din ce cutie scoti fructul si cum procedezi mai departe pentru a afla continutul celor 3 cutii?"
      }
    ],
    "max_tokens": 1024,
    "temperature": 0.6
  }'
```
*Urmărește secțiunea `<think>` din răspuns pentru a vedea cum modelul rezolvă ghicitoarea înainte de a da răspunsul final.*