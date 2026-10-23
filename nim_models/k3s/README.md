# NVIDIA NIM on K3s / Lightweight Kubernetes (Enterprise Architecture)

This module provides the enterprise orchestration blueprint for deploying **NVIDIA NIM microservices on Kubernetes (K3s)** using Helm charts, Kubernetes manifests, and GPU resource management.

---

## 1. Architectural Strategy

While Docker Compose is ideal for single-node development and quick benchmarking, **Kubernetes (K3s)** delivers production-grade enterprise governance:

* **Declarative Orchestration:** Version-controlled Helm values and GitOps deployment patterns.
* **Storage Governance & Cache Sharing:** PersistentVolumeClaims (PVCs) mapped to shared enterprise storage (e.g., hostPath `/root/.cache/nim` on GPU nodes or NFS shares from on-prem NAS), avoiding multi-gigabyte redundant weight downloads.
* **Dynamic Scaling & High Availability:** Kubernetes Horizontal Pod Autoscaler (HPA) triggered by Triton inference metrics (queue depth, request latency).
* **Ingress & Traffic Routing:** Unified API routing via Traefik or NGINX Ingress, exposing OpenAI-compatible endpoints with TLS termination.

---

## 2. Directory Structure

```text
nim_models/k3s/
├── helm/                         # NVIDIA NIM Helm Charts or subcharts
├── values/                       # Model-specific Helm values
│   ├── values-deepseek-r1-8b.yaml # GPU limits, nodeSelector, tolerations
│   └── values-llama-3.1-8b.yaml   # Resources, cache volume mounts, health probes
├── manifests/                    # Native K8s manifests
│   ├── 00-namespace.yaml         # Dedicated 'nim-serving' namespace
│   ├── 01-secret-ngc.yaml        # NGC API Key Kubernetes secret
│   ├── 02-cache-pvc.yaml         # PVC for model weight caching
│   └── 03-ingress.yaml           # Ingress routing rules
└── README.md                     # This documentation
```

---

## 3. Prerequisites for GPU-Enabled K3s

Before deploying NIM Helm charts to a K3s cluster:

1. **GPU Drivers & NVIDIA Container Toolkit:**
   Must be installed on the worker node with persistence mode enabled (`nvidia-smi -pm 1`).
2. **K3s Configured with NVIDIA Runtime:**
   K3s must use `containerd` configured with the NVIDIA runtime (`/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl`).
3. **NVIDIA GPU Operator or Device Plugin:**
   Deploy the official NVIDIA k8s device plugin:
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.16.1/deployments/static/gpu-feature-discovery-daemonset.yaml
   kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.16.1/deployments/static/nvidia-device-plugin.yml
   ```
4. **NGC Secret:**
   Store the NGC API Key as a Kubernetes Secret:
   ```bash
   kubectl create secret generic ngc-secret \
     --from-literal=NGC_API_KEY="$NGC_API_KEY" \
     -n nim-serving
   ```

---

## 4. Planned Helm Deployment Pattern

NVIDIA publishes official Helm charts for LLM NIMs. A deployment will follow this pattern:

```bash
# Add NVIDIA Helm repository
helm repo add nvidia-nim https://helm.ngc.nvidia.com/nim
helm repo update

# Deploy DeepSeek-R1 NIM via Helm
helm upgrade --install nim-deepseek-r1 nvidia-nim/nim-llm \
  -n nim-serving \
  -f nim_models/k3s/values/values-deepseek-r1-8b.yaml
```

---

## 5. Storage Sizing & PersistentVolume Strategy

| Storage Type | Mount Path | Recommended Size | Role |
| :--- | :--- | :--- | :--- |
| **Model Weight Cache** | `/opt/nim/.cache` | 100 GB+ (hostPath / NFS) | Prevents redundant model downloads across Pod restarts. |
| **Shared Memory (`/dev/shm`)** | EmptyDir (Memory) | 16 GiB | Essential for TensorRT-LLM and Triton inter-process communication. |

---

## 6. Testing & Validating K3s NIM Deployments

The Python test client in `tests/test_nim_api.py` is **100% compatible** with K3s:

```bash
# Test through K3s Ingress or NodePort
python3 tests/test_nim_api.py --host <K3S_NODE_IP> --port 8000 --hide-think
```
