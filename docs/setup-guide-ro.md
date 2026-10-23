# Ghid Complet: Configurare NVIDIA NIM (Typhoon 2) pe Ubuntu 22.04 LTS (GCP)

Acest ghid oferă instrucțiunile complete, scripturile optimizate și explicațiile pas cu pas pentru configurarea unui server de inferență de înaltă performanță folosind **NVIDIA NIM** pe o instanță Google Cloud Platform (GCP).

Ghidul este optimizat pentru o mașină virtuală de tip **Spot** cu specificațiile:
* **Machine type:** `g2-standard-8` (8 vCPUs, 32 GB RAM)
* **GPU:** 1 x NVIDIA L4 (24GB VRAM)
* **OS:** Ubuntu 22.04 LTS Minimal

---

## Arhitectura Sistemului: Unde rulează componentele?

Pentru a menține sistemul de operare gazdă curat și stabil, infrastructura este împărțită inteligent:

1. **Pe Instanța Gazdă (Ubuntu 22.04):** Se instalează doar componentele de bază brute – Driverul grafic NVIDIA, Docker și NVIDIA Container Toolkit (podul de legătură).
2. **În interiorul Containerului Docker (NVIDIA NIM):** Vin preinstalate direct de către NVIDIA toate uneltele complexe de calcul: **CUDA Toolkit** și **TensorRT-LLM** (motorul de optimizare grafică). Nu este nevoie să le instalezi manual pe server!

---

## Pasul 1: Pregătirea Sistemului și Activarea Plăcii Video

*Rulează acest script imediat după crearea instanței, ca utilizator root (`sudo -i`).*

```bash
#!/bin/bash
# Intrăm în modul administrator pentru permisiuni totale
sudo -i

echo "=== PASUL 1: Configurare memorie SWAP și Driver NVIDIA ==="

# =========================================================================
# 1. OPTIMIZARE MEMORIE (SWAP 32GB)
# Mașina g2-standard-8 are doar 32GB RAM fizic. În faza de încărcare a modelului
# în GPU, procesul are nevoie de memorie suplimentară pe disc (SWAP). 
# Fără acest pas, sistemul va închide procesul forțat (eroare Out-of-Memory / Connection Reset).
# =========================================================================
echo "Configurare fișier SWAP de 32GB..."
fallocate -l 32G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# Activare permanentă a SWAP-ului la repornire
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# =========================================================================
# 2. INSTALARE DRIVERE NVIDIA
# Actualizăm listele și instalăm driverul server-headless (fără interfață grafică).
# Acesta activează cipul grafic L4 și permite comunicarea cu sistemul de operare.
# =========================================================================
echo "Instalare drivere NVIDIA..."
apt update
apt install --no-install-recommends nvidia-headless-550-server nvidia-utils-550-server -y

echo "Instalare completă. Se repornește instanța pentru activarea driverului..."
reboot
```

---

## Pasul 2: Instalarea Docker și a Podului NVIDIA (Container Toolkit)

*După ce instanța a repornit, reconectează-te prin SSH și rulează acest script ca root (`sudo -i`).*

```bash
#!/bin/bash
sudo -i

echo "=== PASUL 2: Instalare Docker și NVIDIA Container Toolkit ==="

# =========================================================================
# 1. INSTALARE DOCKER
# Instalează motorul Docker care va rula containerul izolat NVIDIA NIM.
# =========================================================================
echo "Instalare Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# =========================================================================
# 2. INSTALARE NVIDIA CONTAINER TOOLKIT
# În mod nativ, Docker este complet izolat de hardware. Acest toolkit acționează
# ca un pod, dându-i voie containerului Docker să acceseze direct resursele GPU-ului L4.
# =========================================================================
echo "Configurare repository și instalare NVIDIA Container Toolkit..."
apt update && apt install gnupg -y

# Adăugarea cheilor oficiale de securitate NVIDIA
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg --yes
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list |   sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' |   tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt-get update
apt-get install -y nvidia-container-toolkit

# Configurare Docker pentru a folosi runtime-ul NVIDIA
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

# =========================================================================
# 3. CREARE DOSAR CACHE PENTRU MODELE
# Creăm folderul pe server unde NIM va descărca și va păstra modelul stocat.
# Permisiunile 777 asigură că utilizatorul din interiorul Docker poate scrie pe disc.
# =========================================================================
mkdir -p ~/.cache/nim
chmod 777 ~/.cache/nim

echo "=== VERIFICARE INFRASTRUCTURĂ ==="
# Rulează un container de test ca să verifici dacă Docker vede placa video
docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi
```

---

## Pasul 3: Autentificarea și Rularea Modelului 
export NGC_API_KEY="nvapi-PASTE_NEW_KEY_HERE"

3.1 Typhoon 2 în Fundal

*Rulează acest script asigurându-te că ai înlocuit textul de la cheia API cu token-ul tău real.*

```bash
#!/bin/bash
sudo -i

echo "=== PASUL 3: Pornire NVIDIA NIM (Typhoon 2) ==="

# =========================================================================
# 1. AUTENTIFICARE NVIDIA NGC Registry
# Setăm cheia ca variabilă de mediu și ne logăm în serverul securizat NVIDIA.
# =========================================================================
# export NGC_API_KEY="nvapi-PASTE_NEW_KEY_HERE"
printf '%s' "$NGC_API_KEY" | docker login nvcr.io -u '$oauthtoken' --password-stdin

# =========================================================================
# 2. RULARE ÎN MOD DETACHED (-d)
# Rulăm containerul în fundal. Chiar dacă închizi sesiunea SSH sau apeși CTRL+C,
# serverul va continua să ruleze în siguranță pe mașină.
# =========================================================================
echo "Lansare container Typhoon 2 în fundal..."
docker run -d --name typhoon2   --runtime=nvidia --gpus all   -e NGC_API_KEY=$NGC_API_KEY   -v ~/.cache/nim:/opt/nim/.cache   -p 8000:8000   nvcr.io/nim/scb10x/llama3.1-typhoon2-8b-instruct:1

# =========================================================================
# 3. MONITORIZARE LIVE A COMPILĂRII
# Prima pornire durează în jur de 5 minute deoarece TensorRT-LLM compilează 
# modelul special pentru placa L4. Poți ieși oricând din loguri cu CTRL + C.
# =========================================================================
echo "Afișare loguri live. Așteaptă mesajul 'vLLM/Triton Server is ready!'"
docker logs -f typhoon2
```

3.2 deepseek-r1-distill-llama-8b în Fundal
######################

export NGC_API_KEY="nvapi-PASTE_NEW_KEY_HERE"

 =========================================================================
# AUTENTIFICARE ȘI CHEIE API
# Ne asigurăm că variabila de mediu este setată corect în sesiunea curentă.
# (Înlocuiește cu cheia ta reală dacă ai deschis un terminal SSH nou!)
# =========================================================================
# export NGC_API_KEY="nvapi-PASTE_NEW_KEY_HERE"
printf '%s' "$NGC_API_KEY" | docker login nvcr.io -u '$oauthtoken' --password-stdin

# =========================================================================
# 3. RULARE DEEPSEEK-R1 NIM ÎN FUNDAL
# Lansăm noul container în fundal (-d). Mapăm același folder de cache 
# pentru ca modelele să nu se piardă dacă mașina repornește.
# =========================================================================
echo "Lansare container DeepSeek-R1 în fundal..."
docker run -d --name deepseek-r1 \
  --runtime=nvidia --gpus all \
  -e NGC_API_KEY=$NGC_API_KEY \
  -v ~/.cache/nim:/opt/nim/.cache \
  -p 8000:8000 \
  nvcr.io/nim/deepseek-ai/deepseek-r1-distill-llama-8b:latest

# =========================================================================
# 4. MONITORIZARE LIVE A DESCARCĂRII ȘI COMPILĂRII
# Deoarece este un model complet nou, NIM va descărca straturile rețelei 
# neuronale și va genera engine-ul TensorRT-LLM optimizat pentru L4.
# =========================================================================
echo "Afișare loguri live pentru DeepSeek. Poți ieși oricând din loguri cu CTRL + C."
docker logs -f deepseek-r1

---

## Schimbarea sau ștergerea unui model

Pe aceeași mașină poate exista un singur container care folosește portul `8000`.
Oprește și șterge containerul curent înainte să pornești alt model:

```bash
docker ps -a
docker rm -f deepseek-r1 2>/dev/null || true
docker rm -f typhoon2 2>/dev/null || true
docker rm -f starcoder 2>/dev/null || true
```

Pentru a șterge și imaginea Docker:

```bash
docker image ls
docker image rm nvcr.io/nim/deepseek-ai/deepseek-r1-distill-llama-8b:latest
```

Dacă imaginea este folosită de un container, șterge întâi containerul. Pentru a
forța ștergerea imaginii:

```bash
docker image rm -f nvcr.io/nim/deepseek-ai/deepseek-r1-distill-llama-8b:latest
```

Cache-ul NIM este separat de imagine. Păstrează-l dacă vei reveni la model:

```bash
du -sh ~/.cache/nim
```

Șterge cache-ul doar dacă vrei să descarci și să compilezi modelul complet din nou:

```bash
rm -rf ~/.cache/nim/*
```

Pentru a adăuga alt model, păstrează autentificarea NGC și schimbă imaginea:

```bash
printf '%s' "$NGC_API_KEY" | \
  docker login nvcr.io -u '$oauthtoken' --password-stdin

docker run -d --name new-model \
  --runtime=nvidia --gpus all \
  -e NGC_API_KEY="$NGC_API_KEY" \
  -v "$HOME/.cache/nim:/opt/nim/.cache" \
  -p 8000:8000 \
  nvcr.io/nim/ORGANIZATION/MODEL:TAG
```

Înlocuiește `new-model` și `nvcr.io/nim/ORGANIZATION/MODEL:TAG` cu numele real
al modelului din catalogul NGC. Nu porni două modele simultan pe portul `8000`.

## Pasul 4: Testarea Serverului de AI (API compatibil OpenAI)

După ce în logurile de la Pasul 3 apare linia finală `vLLM/Triton Server is ready!`, serverul este activ. Îl poți apela din interiorul instanței sau din exterior (dacă portul `8000` este deschis în Firewall-ul GCP).


4.1 Typhoon 2 Testare API
### Test prin Terminal (cURL)
```bash
curl -X 'POST'   'http://localhost:8000/v1/chat/completions'   -H 'accept: application/json'   -H 'Content-Type: application/json'   -d '{
    "model": "scb10x/llama3.1-typhoon2-8b-instruct",
    "messages": [
      {
        "role": "user",
        "content": "Salut! Zi-mi în trei cuvinte ce poți face."
      }
    ],
    "temperature": 0.7,
    "stream": false
  }'
```

### Integrare în Cod (Python)
Serverul tău NIM expune aceleași rute ca și OpenAI, deci poți folosi librăria lor nativă:

```python
import openai

client = openai.OpenAI(
    base_url="http://<IP_PUBLIC_GCP>:8000/v1",
    api_key="nu-e-nevoie-de-cheie"  # Serverul tău local nu cere autentificare externă
)

response = client.chat.completions.create(
    model="scb10x/llama3.1-typhoon2-8b-instruct",
    messages=[{"role": "user", "content": "Explică pe scurt ce este NVIDIA NIM."}]
)

print(response.choices[0].message.content)
```

---

## Comenzi utile pentru Mentenanță și Depanare

* **Verificare loguri ascunse:** `docker logs --tail 20 typhoon2`
* **Urmărire utilizare memorie RAM (faza de boot):** `free -h` sau `htop`
* **Vizualizare live a consumului plăcii video:** `nvidia-smi -l 2`
* **Oprire forțată și ștergere container:** `docker rm -f typhoon2`
* **Accesare consolă direct în interiorul containerului NIM (unde se află CUDA):**
  ```bash
  docker exec -it typhoon2 bash
  # Rulează înăuntru pentru verificare CUDA: nvcc --version
  # Pentru a ieși, scrie: exit
  ```

################


curl -X 'POST' \
  'http://104.198.49.80:8000/v1/chat/completions' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "scb10x/llama3.1-typhoon2-8b-instruct",
    "messages": [
      {
        "role": "user",
        "content": "Salut! Zi-mi un singur cuvânt de bucurie."
      }
    ],
    "temperature": 0.7,
    "max_tokens": 20,
    "stream": false
  }'
  
  
  
  root@gpu-worker-p3sb:~# ^C
root@gpu-worker-p3sb:~# curl -X 'POST' \
  'http://104.198.49.80:8000/v1/chat/completions' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "scb10x/llama3.1-typhoon2-8b-instruct",
    "messages": [
      {
        "role": "user",
        "content": "Salut! Zi-mi un singur cuvânt de bucurie."
      }
    ],
    "temperature": 0.7,
    "max_tokens": 20,
    "stream": false
  }'
{"id":"chat-76fc2b2374104dacaae606e11f0e9414","object":"chat.completion","created":1787154304,"model":"scb10x/llama3.1-typhoon2-8b-instruct","choices":[{"index":0,"message":{"role":"assistant","content":"Salut! Sărbătorire!"},"logprobs":null,"finish_reason":"stop","stop_reason":null}],"usage":{"prompt_tokens":53,"total_tokens":63,"completion_tokens":10},"prompt_logprobs":null}root@gpu-worker-p3sb:~# 


4.2 deepseek-r1-distill-llama-8b Testare API

IP="34.44.244.230"

curl -X 'POST' \
  "http://$IP:8000/v1/chat/completions" \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "deepseek-ai/deepseek-r1-distill-llama-8b",
    "messages": [
      {
        "role":"user",
        "content":"Hello! How are you?"
      },
      {
        "role":"assistant",
        "content":"Hi! I am quite well, how can I help you today?"
      },
      {
        "role":"user",
        "content":"Can you write me a song?"
      }
    ],
    "top_p": 1,
    "n": 1,
    "max_tokens": 15,
    "stream": true,
    "frequency_penalty": 1.0,
    "stop": ["hello"]
  }'

IP="<VM_PUBLIC_IP>"

curl -X 'POST' \
  "http://$IP:8000/v1/chat/completions" \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "deepseek-ai/deepseek-r1-distill-llama-8b",
    "messages": [
      {
        "role": "user",
        "content": "I have a 3-liter jug and a 5-liter jug. I have an unlimited supply of water. How can I measure exactly 4 liters of water? Explain step by step."
      }
    ],
    "temperature": 0.6,
    "max_tokens": 500,
    "stream": false
  }'
################# Test openapi in cline:

docker run -d --name starcoder \
  --runtime=nvidia --gpus all \
  -e NGC_API_KEY=$NGC_API_KEY \
  -v ~/.cache/nim:/opt/nim/.cache \
  -p 8000:8000 \
  nvcr.io/nim/bigcode/starcoder2-7b:latest


  # Exemple working triton server on docker logs:

  INFO 2026-08-20 13:28:45.132 build_utils.py:235] Total time of reading and converting rank0 checkpoint: 0.51 s
INFO 2026-08-20 13:32:05.263 build_utils.py:243] Total time of building rank0 engine: 200.13 s
INFO 2026-08-20 13:32:06.805 utils.py:193] Using provided selected GPUs list [0]
INFO 2026-08-20 13:32:06.805 utils.py:380] Using 0 bytes of gpu memory for PEFT cache
INFO 2026-08-20 13:32:06.805 utils.py:385] Engine size in bytes 16288518660
INFO 2026-08-20 13:32:06.822 utils.py:389] available device memory 23659151360
INFO 2026-08-20 13:32:06.822 utils.py:400] Setting free_gpu_memory_fraction to 0.9
INFO 2026-08-20 13:32:15.313 api_server.py:346] An example cURL request:
curl -X 'POST' \
  'http://0.0.0.0:8000/v1/chat/completions' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "deepseek-ai/deepseek-r1-distill-llama-8b",
    "messages": [
      {
        "role":"user",
        "content":"Hello! How are you?"
      },
      {
        "role":"assistant",
        "content":"Hi! I am quite well, how can I help you today?"
      },
      {
        "role":"user",
        "content":"Can you write me a song?"
      }
    ],
    "top_p": 1,
    "n": 1,
    "max_tokens": 15,
    "stream": true,
    "frequency_penalty": 1.0,
    "stop": ["hello"]
  }'

INFO 2026-08-20 13:32:15.371 api_server.py:183] Available routes are:
INFO 2026-08-20 13:32:15.371 api_server.py:191] Route: /openapi.json, Methods: HEAD, GET
INFO 2026-08-20 13:32:15.371 api_server.py:191] Route: /docs, Methods: HEAD, GET
INFO 2026-08-20 13:32:15.371 api_server.py:191] Route: /docs/oauth2-redirect, Methods: HEAD, GET
INFO 2026-08-20 13:32:15.371 api_server.py:191] Route: /v1/chat/completions, Methods: POST
INFO 2026-08-20 13:32:15.371 api_server.py:191] Route: /v1/completions, Methods: POST
INFO 2026-08-20 13:32:15.371 api_server.py:191] Route: /experimental/ls/inference/chat_completion, Methods: POST
INFO 2026-08-20 13:32:15.371 api_server.py:191] Route: /experimental/ls/inference/completion, Methods: POST
INFO 2026-08-20 13:32:15.371 api_server.py:191] Route: /v1/health/ready, Methods: GET
INFO 2026-08-20 13:32:15.371 api_server.py:191] Route: /v1/health/live, Methods: GET
INFO 2026-08-20 13:32:15.371 api_server.py:191] Route: /v1/models, Methods: GET
INFO 2026-08-20 13:32:15.371 api_server.py:191] Route: /v1/metadata, Methods: GET
INFO 2026-08-20 13:32:15.371 api_server.py:191] Route: /v1/version, Methods: GET
INFO 2026-08-20 13:32:15.372 api_server.py:191] Route: /v1/health/live, Methods: GET
INFO 2026-08-20 13:32:15.372 api_server.py:191] Route: /v1/health/ready, Methods: GET
INFO 2026-08-20 13:32:15.372 api_server.py:191] Route: /v1/metrics, Methods: GET
INFO 2026-08-20 13:32:15.372 api_server.py:191] Route: /v1/license, Methods: GET
INFO 2026-08-20 13:32:15.372 api_server.py:191] Route: /v1/metadata, Methods: GET
INFO 2026-08-20 13:32:15.372 api_server.py:191] Route: /v1/manifest, Methods: GET
INFO 2026-08-20 13:32:15.462 server.py:82] Started server process [99]
INFO 2026-08-20 13:32:15.462 on.py:48] Waiting for application startup.
INFO 2026-08-20 13:32:15.487 on.py:62] Application startup complete.
INFO 2026-08-20 13:32:15.490 server.py:214] Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
INFO 2026-08-20 13:35:17.837 httptools_impl.py:481] 203.0.113.10:57912 - "POST /v1/chat/completions HTTP/1.1" 200


###########
 docker ps
CONTAINER ID   IMAGE                                                         COMMAND                  CREATED             STATUS             PORTS                                         NAMES
8d5bebe030c9   nvcr.io/nim/deepseek-ai/deepseek-r1-distill-llama-8b:latest   "/opt/nvidia/nvidia_…"   About an hour ago   Up About an hour   0.0.0.0:8000->8000/tcp, [::]:8000->8000/tcp   deepseek-r1
root@gpu-worker-4cv5:~# 

docker logs --tail 30 deepseek-r1