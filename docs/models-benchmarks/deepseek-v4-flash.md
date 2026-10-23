https://catalog.ngc.nvidia.com/orgs/nim/deepseek-ai/containers/deepseek-v4-flash-0731/-

DeepSeek-V4-Flash-0731 NIM Container Overview
Description:
The DeepSeek-V4-Flash-0731 NIM Container is a deployable inference container for serving DeepSeek-V4-Flash-0731 through OpenAI-compatible APIs with SGLang.

The container components are ready for commercial or non-commercial use.

Third-Party Community Consideration
The model embedded in the container is not owned or developed by NVIDIA. This model has been developed and built to a third-party's requirements for this application and use case; see link to Non-NVIDIA DeepSeek-V4-Flash-0731 Model Card.

License/Terms of Use:
GOVERNING DOWNLOAD TERMS: Use of the NIM container is governed by the NVIDIA Software License Agreement and Product-Specific Terms for NVIDIA AI Products. Use of the model is governed by the NVIDIA Open Model Agreement. ADDITIONAL INFORMATION: MIT License.

You are responsible for ensuring that your use of NVIDIA provided models complies with all applicable laws.

Deployment Geography:
Global

Release Date:
NGC 08/18/2026 via link

Program Classes:
The DeepSeek-V4-Flash-0731 NIM Container includes the following model:

Model Name & Link	Use Case	How to Pull the Model
DeepSeek-V4-Flash-0731	Text generation, coding, reasoning, long-context, and agentic tool-use workflows	Automatic (embedded in container)
Deployment Details:
The container exposes OpenAI-compatible chat-completions and model-discovery endpoints for application integration.

Our AI models are designed and/or optimized to run on NVIDIA GPU-accelerated systems. By leveraging NVIDIA's hardware (e.g. GPU cores) and software frameworks (e.g., CUDA libraries), the model achieves faster training and inference times compared to CPU-only solutions.

Reference(s):
DeepSeek-V4-Flash-0731 Model Page
NVIDIA NIM for LLMs Documentation
Container Version(s)
1.11.0-variant

Security Common Vulnerabilities and Exposures (CVEs)
Please review the Security Scanning tab on NGC to view the latest security scan results. For certain open-source vulnerabilities listed in the scan results, NVIDIA provides a response in the form of a Vulnerability Exploitability eXchange (VEX) document. The VEX information can be reviewed and downloaded from the Security Scanning tab.

Ethical Considerations:
NVIDIA believes Trustworthy AI is a shared responsibility and we have established policies and practices to enable development for a wide array of AI applications. Developers should work with their internal developer team to ensure these software components meet requirements for the relevant industry and use case and address unforeseen product misuse.

Please report quality, risk, security vulnerabilities or NVIDIA AI Concerns here.

Get Help
Getting started with the NIM
Deploying and integrating the NIM is straightforward thanks to our industry standard APIs. Visit the NIM documentation for release documentation, deployment guides and more.

NVIDIA Developer Community Forum
Get access to community knowledge base articles and support cases (NVIDIA Developer Forums).



# 1. Eliberează memoria
docker rm -f qwen-coder

# 2. Asigură-te că cheia e exportată
export NGC_API_KEY="cheia_ta_aici_care_incepe_cu_nvapi"

# 3. Lansează DeepSeek-V4-Flash (Varianta cu SGLang)
echo "Lansare DeepSeek-V4-Flash..."
docker run -d --name v4-flash \
  --runtime=nvidia --gpus all \
  -e NGC_API_KEY=$NGC_API_KEY \
  -v ~/.cache/nim:/opt/nim/.cache \
  -p 8000:8000 \
  nvcr.io/nim/deepseek-ai/deepseek-v4-flash-0731:latest

# 4. Verifică logurile să vezi dacă pornește SGLang cu succes
docker logs -f v4-flash