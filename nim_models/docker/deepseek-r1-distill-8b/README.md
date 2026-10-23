# DeepSeek-R1-Distill-Llama-8B (NVIDIA NIM)

Acest modul oferă rețeta completă pentru rularea containerului de inferență **DeepSeek-R1-Distill-Llama-8B** prin NVIDIA NIM pe GPU-uri NVIDIA (ex. L4 24GB VRAM pe GCP).

---

## 1. Specificații Tehnice & Resurse Necesare

* **Imagine Docker:** `nvcr.io/nim/deepseek-ai/deepseek-r1-distill-llama-8b:latest`
* **VRAM recomandat:** Minim 16 GB (rulează optim pe **1x NVIDIA L4 24GB**)
* **RAM Gazdă:** Minim 32 GB RAM (+ 32 GB Swap configurat)
* **Spațiu Disc:** ~30 GB pentru straturi și engine-ul TensorRT compilat
* **Motor Inferență intern:** TensorRT-LLM / vLLM integrat în NIM

---

## 2. Pornire Rapidă

### Opțiunea A: Folosind scriptul bash

```bash
cd nim_models/docker/deepseek-r1-distill-8b
chmod +x run.sh stop.sh
./run.sh
```

### Opțiunea B: Folosind Docker Compose

```bash
cd nim_models/docker/deepseek-r1-distill-8b
docker compose up -d
```

---

## 3. Monitorizare & Verificare

### Vizualizare loguri în timp real:
```bash
docker logs -f deepseek-r1
```

> ⏳ *La prima pornire, NIM descarcă modelul și compilează planul TensorRT-LLM. Acest proces poate dura 3-8 minute. Când este gata, în loguri va apărea:* `Application startup complete. Uvicorn running on http://0.0.0.0:8000`.

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
    "model": "deepseek-ai/deepseek-r1-distill-llama-8b",
    "messages": [
      {"role": "user", "content": "Care este viteza luminii in vid? Raspunde pe scurt."}
    ],
    "temperature": 0.2,
    "max_tokens": 150
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
