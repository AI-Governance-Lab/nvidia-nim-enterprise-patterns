# LiteLLM pe aceeași mașină cu NVIDIA NIM

Status verificat la `2026-08-21`:

- VM: `gpu-worker-dsdw`
- Zonă: `us-east1-b`
- IP extern curent: `<VM_PUBLIC_IP>`
- NIM: port `8000`
- LiteLLM: port `4000`
- model expus prin LiteLLM: `deepseek-code`

NIM rulează pe portul `8000`, iar LiteLLM va expune un API OpenAI-compatible pe portul `4000`:

```text
Cline -> http://IP_PUBLIC:4000/v1 -> LiteLLM -> http://127.0.0.1:8000/v1 -> NVIDIA NIM
```

## 1. Verifică NIM

Rulează pe serverul GCP:

```bash
docker ps
curl http://127.0.0.1:8000/v1/models
```

Modelul trebuie să fie disponibil cu ID-ul:

```text
deepseek-ai/deepseek-r1-distill-llama-8b
```

## 2. Creează configurația LiteLLM

```bash
mkdir -p ~/litellm
cd ~/litellm

cat > config.yaml <<'EOF'
model_list:
  - model_name: deepseek-code
    litellm_params:
      model: openai/deepseek-ai/deepseek-r1-distill-llama-8b
      api_base: http://127.0.0.1:8000/v1
      api_key: dummy

general_settings:
  master_key: sk-local-litellm

litellm_settings:
  drop_params: true
  request_timeout: 600
EOF
```

`deepseek-code` este aliasul pe care îl vei folosi în Cline. Dacă vrei să păstrezi ID-ul original, schimbă `model_name` cu `deepseek-ai/deepseek-r1-distill-llama-8b`.

Configurația folosește `api_key: dummy` doar pentru conexiunea internă LiteLLM -> NIM.
Cheia cerută de clienți este cheia LiteLLM din `general_settings.master_key`:
`sk-local-litellm`.

## 3. Pornește LiteLLM în Docker

Se folosește network-ul host pentru ca Docker să acceseze NIM-ul local pe `127.0.0.1:8000`:

```bash
docker rm -f litellm-proxy 2>/dev/null || true

docker run -d \
  --name litellm-proxy \
  --restart unless-stopped \
  --network host \
  -v "$HOME/litellm/config.yaml:/config.yaml:ro" \
  --entrypoint litellm \
  ghcr.io/berriai/litellm:main \
  --config /config.yaml \
  --port 4000
```

Verifică pornirea:

```bash
docker ps --filter name=litellm-proxy
docker logs --tail 100 litellm-proxy
curl http://127.0.0.1:4000/v1/models \
  -H 'Authorization: Bearer sk-local-litellm'
```

Un răspuns `{"detail":"Not Found"}` pe `/health/liveliness` nu înseamnă că
proxy-ul este oprit; unele versiuni LiteLLM nu expun această rută. Confirmarea
reală este răspunsul de la `/v1/models` sau de la testul de chat de mai jos.

Dacă vezi în loguri modele `azure/...` sau `gpt-4`, containerul nu a încărcat fișierul tău. Verifică mount-ul astfel:

```bash
docker run --rm \
  --entrypoint sh \
  -v "$HOME/litellm/config.yaml:/config.yaml:ro" \
  ghcr.io/berriai/litellm:main \
  -c 'cat /config.yaml'
```

Output-ul trebuie să conțină `deepseek-code`, nu `azure` sau `gpt-4`.

Verifică și configurația din containerul pornit:

```bash
docker exec litellm-proxy sh -c 'cat /config.yaml'
```

Dacă proxy-ul a eșuat deja, recreează-l după comanda de mai sus:

```bash
docker rm -f litellm-proxy 2>/dev/null || true
```

## 4. Testează proxy-ul

```bash
curl -X POST http://127.0.0.1:4000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer sk-local-litellm' \
  -d '{
    "model": "deepseek-code",
    "messages": [
      {"role": "user", "content": "Hello, answer in one sentence."}
    ],
    "temperature": 0.2,
    "stream": false
  }'
```

Rezultatul corect trebuie să conțină:

```json
"model": "deepseek-ai/deepseek-r1-distill-llama-8b"
```

și un câmp `choices[0].message.content`. Pentru DeepSeek-R1 este normal ca
răspunsul să includă secțiunea `<think>...</think>`; aceasta conține raționamentul
modelului și poate fi ascunsă sau filtrată de client.

## 5. Configurează Cline

În Cline folosește:

```text
API Provider: OpenAI Compatible
Base URL: http://<VM_PUBLIC_IP>:4000/v1
API Key: sk-local-litellm
Model ID: deepseek-code
```

Dacă Cline afișează o eroare `400` și `modelId` este
`deepseek-ai/deepseek-r1-distill-llama-8b`, Cline folosește încă configurația
directă către NIM. Pentru LiteLLM, `Model ID` trebuie să fie exact `deepseek-code`.
Nu folosi IP-ul vechi `<OLD_VM_IP>:8000` și nu folosi ID-ul upstream în Cline.

Verifică din PowerShell că LiteLLM expune aliasul corect:

```powershell
curl.exe "http://<VM_PUBLIC_IP>:4000/v1/models" `
  -H "Authorization: Bearer sk-local-litellm"
```

Răspunsul trebuie să conțină:

```json
"id": "deepseek-code"
```

Nu adăuga `/chat/completions` la Base URL. Dacă Cline are opțiunea de streaming,
poți începe cu streaming dezactivat pentru DeepSeek-R1, apoi îl activezi după ce
testul simplu funcționează.

## 6. Configurează Continue

În Continue selectează providerul OpenAI-compatible și folosește:

```yaml
name: deepseek-code
provider: openai
model: deepseek-code
apiBase: http://<VM_PUBLIC_IP>:4000/v1
apiKey: sk-local-litellm
```

În versiunile Continue care folosesc `models:` într-un fișier YAML:

```yaml
models:
  - name: deepseek-code
    provider: openai
    model: deepseek-code
    apiBase: http://<VM_PUBLIC_IP>:4000/v1
    apiKey: sk-local-litellm
    completionOptions:
      temperature: 0.2
      maxTokens: 512
    requestOptions:
      timeout: 600000
```

Pentru Continue instalat local în Windows, păstrează IP-ul public. Timeout-ul
este în milisecunde: `600000` înseamnă 10 minute. `maxTokens` limitează răspunsul
și reduce timpul consumat de secțiunea `<think>` a DeepSeek-R1.

Pentru Continue, dacă răspunsul apare gol, dezactivează temporar streaming-ul
și verifică din nou cererea non-streaming de la secțiunea 4.

### Depanare `UND_ERR_SOCKET`

Această eroare apare de obicei când clientul pierde conexiunea în timpul unui
răspuns streaming. În Cline sau Continue dezactivează temporar streaming-ul și
testează endpoint-ul din calculatorul tău:

```bash
curl --max-time 120 http://<VM_PUBLIC_IP>:4000/v1/models \
  -H 'Authorization: Bearer sk-local-litellm'

curl --max-time 120 -X POST \
  http://<VM_PUBLIC_IP>:4000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer sk-local-litellm' \
  -d '{
    "model": "deepseek-code",
    "messages": [{"role": "user", "content": "Reply with exactly: hello"}],
    "max_tokens": 32,
    "stream": false
  }'
```

Într-un al doilea terminal de pe VM urmărește logurile:

```bash
docker logs -f litellm-proxy
docker logs -f deepseek-r1
```

După modificarea configurației, recreează LiteLLM și rulează din nou comanda de
pornire din secțiunea 3:

```bash
docker rm -f litellm-proxy
```

## 7. IP-ul extern și firewall-ul

IP-ul public actual al VM-ului este:

```text
<VM_PUBLIC_IP>
```

IP-ul VM-ului este efemer și se poate schimba după recrearea MIG-ului. Pentru a
vedea toate instanțele și IP-urile lor publice:

```bash
gcloud compute instances list \
  --project=YOUR_PROJECT_ID
```

Pentru un output mai clar, cu doar nume, zonă, IP public și status:

```bash
gcloud compute instances list \
  --project=YOUR_PROJECT_ID \
  --format='table(name,zone,networkInterfaces[0].accessConfigs[0].natIP,status)'
```

Exemplu pentru instanța curentă:

```bash
gcloud compute instances describe gpu-worker-dsdw \
  --zone=us-east1-b \
  --project=YOUR_PROJECT_ID \
  --format='value(networkInterfaces[0].accessConfigs[0].natIP)'
```

Comanda trebuie să afișeze:

```text
<VM_PUBLIC_IP>
```

Poți salva IP-ul într-o variabilă pentru testare:

```bash
PUBLIC_IP="$(gcloud compute instances describe gpu-worker-dsdw \
  --zone=us-east1-b \
  --project=YOUR_PROJECT_ID \
  --format='value(networkInterfaces[0].accessConfigs[0].natIP)')"

echo "$PUBLIC_IP"
curl "http://${PUBLIC_IP}:4000/v1/models" \
  -H 'Authorization: Bearer sk-local-litellm'
```

Dacă IP-ul clientului tău s-a schimbat, actualizează `my_external_ip` în
`iac-scripts/gcp/mig-nvidia/main-mig.tf`. Dacă IP-ul VM-ului se schimbă, actualizează
doar Base URL-ul din Cline/Continue. Nu confunda IP-ul VM-ului (`<VM_PUBLIC_IP>`)
cu IP-ul extern al calculatorului tău, folosit de firewall.

Portul `4000` trebuie permis din IP-ul clientului. Portul `8000` poate fi închis
public după ce LiteLLM funcționează, fiindcă LiteLLM accesează NIM local prin
`127.0.0.1:8000`.

### Test din Windows PowerShell

Pe Windows, află IP-ul public al calculatorului:

```powershell
$myIp = (Invoke-RestMethod https://api.ipify.org).Trim()
$myIp
```

Acest IP trebuie să fie valoarea lui `my_external_ip` în
`iac-scripts/gcp/mig-nvidia/main-mig.tf`. De exemplu, dacă PowerShell afișează
`203.0.113.25`, setează:

```hcl
default = "203.0.113.25"
```

Apoi, pe mașina unde rulezi Terraform:

```bash
terraform plan -out=plan1
terraform apply plan1
```

Sau fără modificarea fișierului Terraform:

```bash
terraform plan -var="my_external_ip=203.0.113.25" -out=plan1
terraform apply plan1
```

După aplicarea firewall-ului, testează din PowerShell:

```powershell
$baseUrl = "http://<VM_PUBLIC_IP>:4000/v1"
$apiKey = "sk-local-litellm"

curl.exe "$baseUrl/models" `
  -H "Authorization: Bearer $apiKey"

curl.exe "$baseUrl/chat/completions" `
  -X POST `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer $apiKey" `
  -d '{"model":"deepseek-code","messages":[{"role":"user","content":"Reply with exactly: hello"}],"max_tokens":32,"stream":false}'
```

Nu pune IP-ul VM-ului (`<VM_PUBLIC_IP>`) în `my_external_ip`; acel IP este
destinația conexiunii, iar `my_external_ip` este IP-ul sursă al calculatorului
Windows.

### Test din Linux cu VPN

Pe Linux, află IP-ul public de ieșire al VPN-ului:

```bash
MY_IP="$(curl --fail --silent --show-error https://api.ipify.org)"
echo "$MY_IP"
```

Acesta este IP-ul care trebuie permis în firewall prin `my_external_ip`.
Verifică și ruta folosită de conexiune:

```bash
ip route get 1.1.1.1
```

Actualizează Terraform cu IP-ul VPN-ului:

```bash
terraform plan -var="my_external_ip=${MY_IP}" -out=plan1
terraform apply plan1
```

Testează LiteLLM de pe Linux:

```bash
PUBLIC_IP="<VM_PUBLIC_IP>"
API_KEY="sk-local-litellm"

curl --fail --show-error --max-time 30 \
  "http://${PUBLIC_IP}:4000/v1/models" \
  -H "Authorization: Bearer ${API_KEY}"

curl --fail --show-error --max-time 120 \
  -X POST "http://${PUBLIC_IP}:4000/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "model": "deepseek-code",
    "messages": [{"role": "user", "content": "Reply with exactly: hello"}],
    "max_tokens": 32,
    "stream": false
  }'
```

Dacă testul eșuează numai când VPN-ul este pornit, compară IP-urile:

```bash
curl -4 https://api.ipify.org; printf '\n'
curl -6 https://api64.ipify.org; printf '\n'
```

Folosește IPv4-ul returnat de prima comandă în firewall. Dacă VPN-ul schimbă
IP-ul sau ruta, actualizează din nou `my_external_ip` și reaplică Terraform.

## Comenzi utile

```bash
docker logs -f litellm-proxy
docker restart litellm-proxy
docker stop litellm-proxy
```

Portul `4000` trebuie permis în firewall doar pentru IP-ul tău. După ce LiteLLM funcționează, portul `8000` poate fi închis public, deoarece proxy-ul îl accesează local pe aceeași mașină.


## 7. Depanare Avansată: Streaming & Tag-urile `<think>` în Cline / Continue.dev

### Simptom
În timpul utilizării modelelor de raționament (ex. `deepseek-ai/deepseek-r1-distill-llama-8b`) prin NVIDIA NIM în extensii IDE precum **Continue.dev** sau **Cline**:
- În logurile containerului NIM apare răspunsul `POST /v1/chat/completions HTTP/1.1 200 OK`:
  ```text
  INFO httptools_impl.py:481] 198.51.100.25:31408 - "POST /v1/chat/completions HTTP/1.1" 200
  ```
- Cu toate acestea, în interfața extensiei răspunsul apare gol sau conexiunea se întrerupe.

### Cauza Tehnică
1. **Parametri neacceptați de NIM:** Agenții de codare (Cline / Roo Code) trimit câmpuri suplimentare în payload-ul OpenAI (`reasoning_effort`, scheme complexe de `tools`, etc.) pe care serverul strict NVIDIA NIM / Triton le poate respinge cu `400 Bad Request`.
2. **Parsarea SSE Streaming pentru `<think>`:** Modelele DeepSeek-R1 emit mai întâi blocul de raționament `<think>...</think>` în fluxul SSE (`stream: true`), ceea ce poate bloca parserul anumitor versiuni de Continue.dev.

### Soluția Arhitecturală Recomandată
1. **Interpunerea LiteLLM Proxy (`drop_params: true`):**
   - LiteLLM filtrează automat parametrii neacceptați de NIM și expune un endpoint OpenAI-compatible curat pe portul `4000`:
     ```bash
     docker run -d \
       --name litellm-proxy \
       -p 4000:4000 \
       -v $(pwd)/litellm_config.yaml:/app/config.yaml:ro \
       ghcr.io/berriai/litellm:main \
       --config /app/config.yaml --port 4000
     ```
2. **Dezactivarea temporară a Streaming-ului (dacă UI-ul nu afișează răspunsul):**
   - În Continue.dev sau în testele inițiale din Cline, setează `stream: false` și un `timeout` generos (`600000` ms) pentru a permite finalizarea lanțului Chain-of-Thought înainte de afișare.
