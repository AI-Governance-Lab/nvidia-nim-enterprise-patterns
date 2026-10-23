# Ghid Practic: Conectare la un VM Nou după `terraform apply`

Acest ghid oferă pașii exacți, comenzile de copiat direct în terminal și metodele de diagnostic pentru a te conecta rapid la orice instanță GPU nouă creată pe Google Cloud Platform (GCP).

---

## 1. Ce se întâmplă imediat după `terraform apply`?

Când Terraform finalizează aplicarea configurației:
1. **Grupul MIG (Managed Instance Group)** creează o instanță cu un nume generat dinamic (ex: `gpu-worker-xxxx`).
2. **Startup Script-ul (`metadata_startup_script`)** pornește automat pe noul VM:
   - Configurează memoria Swap de 32 GB.
   - Instalează driverele grafice NVIDIA 550 / 580.
   - **Efectuează un restart (reboot) automat al mașinii** pentru activarea modulului de kernel NVIDIA.
   - După repornire, instalează Docker Engine și NVIDIA Container Toolkit.
3. ⏳ **Timp total de așteptare:** Între **3 și 5 minute** de la comanda `terraform apply` până când Docker și GPU-ul sunt 100% gata.

---

## 2. Pasul 1: Detectarea automată a noului VM

Deoarece numele instanței și IP-ul sunt generate dinamic, rulează aceste comenzi pe mașina ta locală pentru a le salva automat în variabile:

```bash
# Salvează numele primului VM GPU activ
VM_NAME=$(gcloud compute instances list --filter="name~'gpu-worker' AND status=RUNNING" --format="get(name)" --limit=1)

# Salvează zona în care a fost creat
VM_ZONE=$(gcloud compute instances list --filter="name~'gpu-worker' AND status=RUNNING" --format="get(zone)" --limit=1)

# Salvează adresa IP publică
VM_IP=$(gcloud compute instances list --filter="name~'gpu-worker' AND status=RUNNING" --format="get(networkInterfaces[0].accessConfigs[0].natIP)" --limit=1)

# Verifică variabilele detectate
echo "----------------------------------------"
echo "VM Detectat : $VM_NAME"
echo "Zona        : $VM_ZONE"
echo "IP Public   : $VM_IP"
echo "----------------------------------------"
```

---

## 3. Pasul 2: Conectarea prin SSH

Alege una dintre următoarele metode de conectare:

### Metoda A: Conectare Recomandată (prin `gcloud`)
Aceasta este cea mai simplă și sigură metodă – gestionează automat cheile SSH și autentificarea:

```bash
gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE"
```

---

### Metoda B: Prin Tunel Securizat IAP (Identity-Aware Proxy)
Dacă rețeaua ta locală sau un firewall de birou blochează portul 22 către IP-uri publice, folosește tunelul IAP oferit de GCP (permis automat prin regula `allow-iap-ssh-gpu` din Terraform):

```bash
gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE" --tunnel-through-iap
```

---

### Metoda C: SSH Tradițional direct la IP Public
Dacă preferi clientul standard `ssh`:

```bash
# Folosind cheia generată automat de gcloud:
ssh -i ~/.ssh/google_compute_engine root@"$VM_IP"

# Sau dacă te conectezi cu utilizatorul tău de sistem:
ssh -i ~/.ssh/google_compute_engine $(whoami)@"$VM_IP"
```

---

## 4. Pasul 3: Cum verifici dacă noul VM a terminat instalarea automată

După ce te-ai conectat prin SSH, rulează următoarele verificări rapide pe VM:

### 1. Urmărește instalarea în timp real:
```bash
tail -f /var/log/gpu-startup-script.log
```
> Când vezi `touch /var/lib/gpu-startup/container-toolkit-installed`, instalarea automată este 100% finalizată. Poți ieși oricând cu `Ctrl + C`.

### 2. Verifică prezența fișierelor de confirmare:
```bash
ls -la /var/lib/gpu-startup/
```
Trebuie să vezi:
* `driver-installed`
* `container-toolkit-installed`

### 3. Verifică starea plăcii GPU:
```bash
nvidia-smi
```
Trebuie să afișeze placa **NVIDIA L4** și memoria VRAM totală (~24 GB).

### 4. Verifică faptul că Docker comunică cu GPU-ul:
```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

---

## 5. Pasul 4: Transferul Fișierelor NIM pe Noul VM

De pe calculatorul tău local (unde ai descărcat repo-ul `nvidia-nim-enterprise-patterns`), copiază directoarele necesare pe noul VM:

```bash
# Copiază directorul nim_models pe noul VM
gcloud compute scp --recurse \
  /root/AI-Governance-Lab/nvidia-nim-enterprise-patterns/nim_models \
  "$VM_NAME":~ --zone="$VM_ZONE"
```

---

## 6. Pasul 5: Lansarea Modelului NIM pe Noul VM

Conectează-te pe VM sau trimite comanda direct de pe mașina locală:

### Exemplu: Lansare Meta Llama 3.1 8B Instruct
```bash
# Rulare directă prin SSH:
gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE" --command="
  cd ~/nim_models/docker/llama-3.1-8b-instruct && \
  chmod +x run.sh stop.sh && \
  ./run.sh
"
```

### Exemplu: Monitorizare loguri de pe mașina locală:
```bash
gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE" --command="docker logs -f llama-3.1-8b"
```

---

## 7. Pasul 6: Testare Inferență (cURL din exterior)

Datorită regulii de firewall `allow_serving_api` (care deschide portul `8000`), poți testa modelul direct trimițând cereri către IP-ul public al noului VM:

```bash
curl -X POST "http://${VM_IP}:8000/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "meta/llama-3.1-8b-instruct",
    "messages": [
      {"role": "user", "content": "Salut! Cine esti si ce model folosesti?"}
    ],
    "temperature": 0.2,
    "max_tokens": 150
  }'
```

---

## 8. Diagnostic Probleme Frecvente (Troubleshooting)

### A. Eroare `Permission denied (publickey)`
Dacă noul VM nu recunoaște cheia SSH:
```bash
# Sincronizează cheile locale cu proiectul GCP:
gcloud compute config-ssh
```

### B. Eroare `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!`
Apare atunci când un VM nou primește un IP pe care l-ai mai folosit în trecut pentru un alt VM:
```bash
# Șterge cheia veche asociată IP-ului:
ssh-keygen -R "$VM_IP"
```

### C. VM-ul nu răspunde la comenzi SSH în primele 2 minute
* Este un comportament **complet normal**. În minutul 2, mașina își dă **reboot automat** pentru activarea driverului NVIDIA. Așteaptă 60-90 de secunde și reconectează-te.
