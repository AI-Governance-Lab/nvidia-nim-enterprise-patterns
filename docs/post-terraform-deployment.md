# Ghid Post-Deployment Terraform: Configurare și Rulare NVIDIA NIM

Acest document descrie fluxul complet de operațiuni post-provizionare infrastructură Terraform pentru clusterul / instanța GPU în Google Cloud Platform (GCP).

---

## 1. Arhitectura & Starea Inițială a Mașinii Virtuale

Când infrastructura este lansată prin Terraform (`iac-scripts/gcp/mig-nvidia` sau `iac-scripts/gcp/standalone-nvidia`), instanța GPU beneficiază de:
* **Hardware:** 1x GPU NVIDIA L4 (24GB VRAM) / T4 (16GB VRAM) pe instanță `g2-standard-12` / `n1-standard-8`.
* **OS:** Ubuntu 22.04 LTS Minimal.
* **Storage:** 150 GB SSD persistent (`pd-balanced`).
* **Startup Script Automatizat (`metadata_startup_script`):**
  1. Creează un fișier de **SWAP de 32 GB** (indispensabil pentru transferul de greutăți în GPU fără crash Out-of-Memory).
  2. Instalează pachetele `nvidia-headless-550-server` și `nvidia-utils-550-server`.
  3. Repornește automat mașina o singură dată pentru activarea driverului de kernel NVIDIA.
  4. Instalează **Docker Engine** și **NVIDIA Container Toolkit** (`nvidia-ctk`).
  5. Configurează runtime-ul Docker implicit cu suport GPU și pornește serviciul Docker.
  6. Creează directorul de cache `/root/.cache/nim`.

---

## 2. Pasul 1: Identificarea Resurselor Create de Terraform

După rularea `terraform apply`, poți identifica instanța creată folosind `gcloud`:

```bash
# Listare instanțe active în proiect
gcloud compute instances list --project=YOUR_PROJECT_ID

# Exemplu output:
# NAME                   ZONE           MACHINE_TYPE    STATUS
# gpu-worker-xxxx        us-central1-a  g2-standard-12  RUNNING
```

Salvați numele instanței și zona într-o variabilă locală de consolă:
```bash
INSTANCE_NAME="gpu-worker-xxxx"
ZONE="us-central1-a"
```

---

## 3. Pasul 2: Conectarea la Instanță prin SSH

Conectarea se poate realiza direct prin utilitarul `gcloud compute ssh`:

```bash
# Conectare directă prin SSH
gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE"
```

> **Notă:** Dacă nu folosești IP public direct sau ești în spatele unui firewall strict, poți folosi Identity-Aware Proxy (IAP) datorită regulii de firewall `allow_iap_ssh` incluse în Terraform:
> ```bash
> gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --tunnel-through-iap
> ```

---

## 4. Pasul 3: Verificarea Stării Instanței și a Driverelor

După conectarea pe VM, verifică dacă scriptul de inițializare a terminat instalarea:

### A. Urmărirea logurilor de startup:
```bash
# Verifică ultimele linii din logul de startup
tail -n 30 /var/log/gpu-startup-script.log
```
Când instalarea este completă, fișierele de stare vor exista în `/var/lib/gpu-startup/`:
* `/var/lib/gpu-startup/driver-installed`
* `/var/lib/gpu-startup/container-toolkit-installed`

### B. Verificarea GPU-ului:
```bash
nvidia-smi
```
Trebuie să afișeze driverul NVIDIA 550.x și placa GPU (ex: `NVIDIA L4`, 24576MiB).

---

## 5. Pasul 4: Structura Modelelor NIM (`nim_models/docker`)

În rădăcina proiectului avem structura modulară pregătită pentru modele:

```text
nvidia-nim-enterprise-patterns/
├── nim_models/
│   └── docker/
│       ├── .env.example
│       ├── common/
│       │   └── docker-compose.base.yml
│       ├── deepseek-r1-distill-8b/
│       │   ├── docker-compose.yml
│       │   ├── run.sh
│       │   ├── stop.sh
│       │   └── README.md
│       ├── llama-3.1-8b-instruct/
│       │   ├── docker-compose.yml
│       │   ├── run.sh
│       │   ├── stop.sh
│       │   └── README.md
│       └── scripts/
│           ├── check_health.sh
│           └── test_inference.sh
```

### Configurarea variabilelor de mediu pe VM:
```bash
cd nvidia-nim-enterprise-patterns/nim_models/docker

# Copiază template-ul de mediu
cp .env.example .env

# Setează cheia ta reală NGC API
export NGC_API_KEY="nvapi-cheia-ta-reala"
echo "NGC_API_KEY=$NGC_API_KEY" > .env
```

---

## 6. Pasul 5: Rularea Modelului DeepSeek-R1-Distill-Llama-8B

Navighează în folderul modelului și lansează containerul:

```bash
cd nim_models/docker/deepseek-r1-distill-8b
chmod +x run.sh stop.sh
./run.sh
```

### Ce se întâmplă la pornire?
1. Se efectuează autentificarea în registrul privat NVIDIA (`nvcr.io`).
2. Se lansează containerul `nvcr.io/nim/deepseek-ai/deepseek-r1-distill-llama-8b:latest`.
3. NIM descarcă automat greutățile modelului în directorul persistent `~/.cache/nim`.
4. NIM compilează motorul **TensorRT-LLM** optimizat pentru arhitectura GPU detectată (Ada Lovelace / L4).

### Monitorizarea procesului de inițializare:
```bash
docker logs -f deepseek-r1
```

Așteaptă până când apare mesajul:
```text
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
```

---

## 7. Pasul 6: Verificarea Stării și Testarea Inferenței

### A. Health Check automatizat:
Din directorul `nim_models/docker`:
```bash
./scripts/check_health.sh localhost 8000 600
```

### B. Test de inferență rapid prin script:
```bash
./scripts/test_inference.sh localhost 8000 "Care sunt cele 3 legi ale roboticii ale lui Asimov?"
```

### C. Test prin apel direct cURL (OpenAI Chat Completions):
```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-ai/deepseek-r1-distill-llama-8b",
    "messages": [
      {"role": "user", "content": "Scrie o poezie scurta despre inteligenta artificiala."}
    ],
    "temperature": 0.3,
    "max_tokens": 150
  }'
```

### D. Rularea suitei de teste Python din proiect:
```bash
python3 tests/test_nim_api.py --host localhost --port 8000
```

---

## 8. Pasul 7: Schimbarea Modelelor & Managementul Memoriei GPU (Model Switching)

GPU-ul L4 are 24 GB VRAM. Pentru a rula un alt model NIM (ex. trecerea de la DeepSeek la Meta Llama 3.1), memoria GPU trebuie eliberată:

### A. Trecerea de la DeepSeek-R1 la Meta-Llama-3.1-8B:
Scripturile `run.sh` includ detecție automată: dacă lansezi `llama-3.1-8b`, containerul `deepseek-r1` este oprit automat și VRAM-ul este eliberat.

Alternativ, manual:
```bash
# 1. Oprește containerul activ DeepSeek-R1
cd nim_models/docker/deepseek-r1-distill-8b
./stop.sh

# 2. Verifică faptul că memoria GPU este complet eliberată (0 MiB used)
nvidia-smi

# 3. Pornește Meta Llama 3.1 8B Instruct
cd ../llama-3.1-8b-instruct
./run.sh

# 4. Urmărește logurile
docker logs -f llama-3.1-8b
```

### B. Revenirea la DeepSeek-R1:
```bash
# Durează sub 30 de secunde deoarece cache-ul TensorRT este deja pe disc!
cd ../deepseek-r1-distill-8b
./run.sh
```

---

## 9. Pasul 8: Oprirea / Ștergerea Infrastructurii (Cost Control)

Pentru a evita costurile inutile pe GCP când nu folosești GPU-ul:

1. **Oprire temporară (dacă e Standalone VM):**
   ```bash
   gcloud compute instances stop "$INSTANCE_NAME" --zone="$ZONE"
   ```
2. **Distrugere completă prin Terraform:**
   ```bash
   cd iac-scripts/gcp/mig-nvidia
   terraform destroy -auto-approve
   ```


### C. Verificarea integrării Docker + GPU:
```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```
