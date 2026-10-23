# Meta Llama 3.1 8B Instruct (NVIDIA NIM)

Acest modul oferă configurația pentru rularea containerului de inferență **Meta Llama 3.1 8B Instruct** prin NVIDIA NIM pe GPU-uri NVIDIA (ex. L4 24GB VRAM pe GCP).

---

## 1. Specificații Tehnice & Resurse Necesare

* **Imagine Docker:** `nvcr.io/nim/meta/llama-3.1-8b-instruct:latest`
* **VRAM recomandat:** Minim 16 GB (rulează optim pe **1x NVIDIA L4 24GB**)
* **RAM Gazdă:** Minim 32 GB RAM (+ 32 GB Swap configurat)
* **Spațiu Disc:** ~28 GB pentru straturi și engine-ul TensorRT-LLM compilat
* **Motor Inferență intern:** TensorRT-LLM integrat în NIM

---

## 2. Pornire Rapidă

### Opțiunea A: Folosind scriptul bash (Recomandat)

Scriptul oprește automat orice alt container NIM activ (ex: DeepSeek-R1) pentru a evita conflictele de port și VRAM:

```bash
cd nim_models/docker/llama-3.1-8b-instruct
chmod +x run.sh stop.sh
./run.sh
```

### Opțiunea B: Folosind Docker Compose

```bash
cd nim_models/docker/llama-3.1-8b-instruct
docker compose up -d
```

---

## 3. Monitorizare & Verificare

### Vizualizare loguri în timp real:
```bash
docker logs -f llama-3.1-8b
```

> ⏳ *La prima descărcare, modelul este transferat în `~/.cache/nim` și compilat cu TensorRT-LLM. Ulterior, pornirile durează sub 30 de secunde.*

### Verificare Health Check:
```bash
curl -s http://localhost:8000/v1/health/ready
```

---

## 4. Testare Inferență

### Exemplu cURL (OpenAI Chat Completions):

```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "meta/llama-3.1-8b-instruct",
    "messages": [
      {"role": "user", "content": "Care sunt avantajele utilizarii microserviciilor? Enumera 3 puncte cheie."}
    ],
    "temperature": 0.2,
    "max_tokens": 200
  }'
```

---

## 5. Oprire Container și Eliberare VRAM

Pentru a opri containerul și a elibera memoria GPU pentru alte modele:

```bash
./stop.sh
# sau
docker compose down
```
