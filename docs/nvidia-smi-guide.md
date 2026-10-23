# NVIDIA System Management Interface (`nvidia-smi`) Guide
### Comprehensive Reference, Practical Commands & Hardware Deep Dive for NVIDIA L4

---

## 1. Overview

`nvidia-smi` (**NVIDIA System Management Interface**) is a command-line utility built on top of the **NVIDIA Management Library (NVML)**. It provides monitoring, management, and diagnostic capabilities for NVIDIA GPU hardware and drivers across Linux and Windows environments.

When serving Large Language Models (LLMs) with **NVIDIA NIM**, `nvidia-smi` is the primary operational tool used to:
* Monitor GPU memory allocation (VRAM) and avoid Out-of-Memory (OOM) errors.
* Track computational utilization during prompt ingestion and token generation.
* Detect thermal throttling and power consumption spikes.
* Inspect running containerized inference processes.

---

## 2. Decoding the `nvidia-smi` Output (L4 Breakdown)

When running `nvidia-smi` on a GCP `g2-standard-12` instance with 1x NVIDIA L4, you see output like this:

```text
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 580.178.04             Driver Version: 580.178.04     CUDA Version: 13.0     |
+-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  NVIDIA L4                      Off |   00000000:00:03.0 Off |                    0 |
| N/A   54C    P0             30W /   72W |       0MiB /  23034MiB |      4%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+

+-----------------------------------------------------------------------------------------+
| Processes:                                                                              |
|  GPU   GI   CI              PID   Type   Process name                        GPU Memory |
|        ID   ID                                                               Usage      |
|=========================================================================================|
|  No running processes found                                                             |
+-----------------------------------------------------------------------------------------+
```

### Detailed Field Breakdown:

| Field | Value (Example) | Meaning & Operational Context |
| :--- | :--- | :--- |
| **Driver Version** | `580.178.04` | Installed host NVIDIA kernel driver version. |
| **CUDA Version** | `13.0` | Maximum CUDA version supported by the driver. Containers can use this or any lower CUDA version. |
| **GPU ID** | `0` | Zero-based index of the physical card in the system. |
| **Name** | `NVIDIA L4` | GPU model identifier (Ada Lovelace data center accelerator). |
| **Persistence-M** | `Off` / `On` | **Persistence Mode**. When `On`, the NVIDIA driver remains loaded in kernel memory even when no application is running, preventing driver re-init delays when spinning up NIM containers. |
| **Bus-Id** | `00000000:00:03.0` | The PCI address on the motherboard (`domain:bus:device.function`). |
| **Disp.A** | `Off` | **Display Active**. Indicates if an active display is driven by the card (`Off` on cloud/headless servers). |
| **Volatile Uncorr. ECC** | `0` | Uncorrected ECC memory error count. `0` indicates no hardware memory corruption. |
| **Fan** | `N/A` | Fan speed percentage. Shows `N/A` on passive enterprise accelerators cooled by server chassis fans. |
| **Temp** | `54C` | Current GPU core temperature. Normal idle is 35°C–55°C; load is 60°C–75°C. Throttling typically starts above 85°C. |
| **Perf** | `P0` | Current **Performance State**, from `P0` (maximum performance) to `P8` (idle power-saving). |
| **Pwr:Usage/Cap** | `30W / 72W` | Current wattage drawn vs. Maximum Power Limit (72W TDP on L4). |
| **Memory-Usage** | `0MiB / 23034MiB` | VRAM occupied vs. total available memory (~24 GB total). |
| **GPU-Util** | `4%` | Percentage of time kernels were executing on the GPU compute cores during the last sample period. |
| **Compute M.** | `Default` | Compute Mode. `Default` allows multiple concurrent processes/threads to access the GPU. |
| **MIG M.** | `N/A` | **Multi-Instance GPU**. Displays `N/A` because hardware MIG is exclusive to A100/H100 chips. The L4 provides 100% of the silicon directly to the VM. |

---

## 3. NVIDIA L4 Architecture & Hardware Deep Dive

The **NVIDIA L4 Tensor Core GPU** is powered by the **Ada Lovelace** enterprise architecture (AD104 chip).

```text
┌─────────────────────────────────────────────────────────────┐
│                 NVIDIA L4 (AD104 Silicium)                  │
├──────────────────────────────┬──────────────────────────────┤
│ 7,424 CUDA Cores             │ 240 4th Gen Tensor Cores     │
│ (General Parallel Compute)   │ (FP8, FP16, BF16, INT8, INT4)│
├──────────────────────────────┼──────────────────────────────┤
│ 24 GB GDDR6 VRAM             │ 300 GB/s Memory Bandwidth    │
│ (Holds 7B - 8B LLM weights)  │ (Fast token generation)      │
├──────────────────────────────┼──────────────────────────────┤
│ PCIe Gen4 x16                │ 72 Watts Maximum TDP         │
│ (Low latency host-to-device) │ (High energy efficiency)     │
└──────────────────────────────┴──────────────────────────────┘
```

### Why is L4 the Ideal Accelerator for 7B - 8B NIM Models?
1. **24 GB GDDR6 VRAM:** Exactly matches the sweet spot for serving models like `Meta Llama-3.1-8B` and `DeepSeek-R1-Distill-8B` (~16 GB model weights + ~6-8 GB KV Cache context window).
2. **4th Gen Tensor Cores with FP8 Support:** Accelerates FP16 and FP8 GEMM (General Matrix Multiply) operations with up to 2.5x inference speedup over previous generation T4 GPUs.
3. **Dedicated PCIe Passthrough:** Unlike shared cloud GPUs, GCP passes the physical device directly to the instance, ensuring deterministic inference latencies.

---

## 4. Essential `nvidia-smi` Commands & Usage

### A. Basic Status & Hardware Overview

```bash
# 1. Standard status overview
nvidia-smi

# 2. List all GPUs with IDs and UUIDs
nvidia-smi -L

# 3. Compact single-line summary
nvidia-smi --format=csv -q | head -n 2
```

---

### B. Querying Specific Metrics (`--query-gpu`)

The `--query-gpu` flag combined with `--format=csv` enables automated scripting and monitoring:

```bash
# 1. Check GPU name, total VRAM, and GPU count
nvidia-smi --query-gpu=count,name,memory.total --format=csv

# 2. Real-time VRAM allocation (Used vs Free vs Total)
nvidia-smi --query-gpu=name,memory.used,memory.free,memory.total --format=csv

# 3. Utilization and Temperature metrics
nvidia-smi --query-gpu=utilization.gpu,utilization.memory,temperature.gpu,power.draw --format=csv

# 4. Clean numeric output without unit suffixes (ideal for scripts/alerting)
nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader,nounits
```

---

### C. Continuous Real-Time Monitoring

```bash
# 1. Refresh every 1 second (Classic watch)
watch -n 1 nvidia-smi

# 2. Built-in loop (native, lower overhead than watch)
nvidia-smi -l 1

# 3. Device Monitoring utility (tabular stream of power, temperature, clocks, utilization)
nvidia-smi dmon -s pucmt -d 1

# 4. Process Monitoring utility (tracks per-process GPU and memory activity)
nvidia-smi pmon -s m -d 1
```

---

### D. Process Management & Freeing VRAM

When running NVIDIA NIM in Docker, you can inspect and terminate processes directly from the host:

```bash
# 1. List active GPU processes with PID and VRAM consumption
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv

# 2. Check which Docker container owns the GPU process
docker ps -q | xargs -I {} docker top {} | grep -E "python|tritonserver|vllm"

# 3. If a process hangs or leaves VRAM locked, kill it:
kill -9 <PID_FROM_NVIDIA_SMI>

# 4. Reset GPU (recover from hung state without VM reboot)
sudo nvidia-smi --gpu-reset
```

---

### E. Enterprise Configuration & Performance Tuning

```bash
# 1. Enable Persistence Mode (Recommended for NIM servers)
# Keeps the NVIDIA driver resident in memory, eliminating initialization overhead
sudo nvidia-smi -pm 1

# 2. Verify Persistence Mode status
nvidia-smi --query-gpu=persistence_mode --format=csv

# 3. Query detailed compute attributes
nvidia-smi -q -d COMPUTE,MEMORY,POWER
```

---

## 5. Automation & Health Check Snippets

### Bash One-Liner: Check if VRAM is Free before Launching NIM
```bash
USED_VRAM=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | tr -d ' ')
if [ "$USED_VRAM" -gt 1000 ]; then
  echo "⚠️ Warning: $USED_VRAM MiB VRAM is already in use! Stop other containers first."
else
  echo "✅ GPU VRAM is clear ($USED_VRAM MiB used). Ready to run NIM."
fi
```

### Quick Verification from Inside a Docker Container
```bash
docker run --rm --gpus all nvcr.io/nim/meta/llama-3.1-8b-instruct:latest nvidia-smi
```

---

## 6. Summary Cheat Sheet

| Task | Command |
| :--- | :--- |
| **Check VRAM** | `nvidia-smi --query-gpu=memory.used,memory.total --format=csv` |
| **Live Stream** | `nvidia-smi dmon -s puc -d 1` |
| **List Compute Apps** | `nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv` |
| **Enable Persistence** | `sudo nvidia-smi -pm 1` |
| **Kill Hung GPU PID** | `sudo kill -9 <PID>` |
| **Reset GPU Card** | `sudo nvidia-smi --gpu-reset` |
