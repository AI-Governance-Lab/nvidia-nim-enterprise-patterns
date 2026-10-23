# =========================================================================
# AUTENTIFICARE ȘI CHEIE API
# Ne asigurăm că variabila de mediu este setată corect în sesiunea curentă.
# (Înlocuiește cu cheia ta reală dacă ai deschis un terminal SSH nou!)
# =========================================================================
export NGC_API_KEY="nvapi-YOUR_NGC_API_KEY"
docker login nvcr.io -u '$oauthtoken' -p $NGC_API_KEY

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