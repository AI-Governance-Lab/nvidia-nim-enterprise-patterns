https://catalog.ngc.nvidia.com/orgs/nim/zai-org/containers/glm-5.2/-

Deployment Details:
Our AI models are designed and/or optimized to run on NVIDIA GPU-accelerated systems. By leveraging NVIDIA's hardware (e.g. GPU cores) and software frameworks (e.g., CUDA libraries), the model achieves faster training and inference times compared to CPU-only solutions.

GLM-5.2 is deployed as a Downloadable NIM container from NGC. Users pull the container image from NGC, configure the service following the NGC container page and NVIDIA NIM documentation, and integrate the standard inference APIs into downstream applications and tools.

Supported Hardware Microarchitecture Compatibility: GPUs: 8 NVIDIA B200 Tensor Core GPUs, 8 NVIDIA H20 Tensor Core GPUs, 8 NVIDIA H200 Tensor Core GPUs, or compatible systems with more than 900 GB of aggregate GPU memory. CPU: x86_64 host CPU compatible with NVIDIA NIM for Large Language Models deployments. Memory: Host memory sized for the selected NIM deployment profile and workload concurrency. Storage: At least 736 GB of disk space for the GLM-5.2 NIM profile.