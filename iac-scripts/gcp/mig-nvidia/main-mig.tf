terraform {
  required_version = ">= 1.3.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0.0" # sau orice versiune mai nouă
    }
  }
}

variable "project_id" {
  description = "GCP Project ID for deployment"
  type        = string
}

variable "compute_service_account_email" {
  description = "Compute Engine Service Account email (format: name@project.iam.gserviceaccount.com)"
  type        = string
}

variable "my_external_ip" {
  description = "External IPv4 address allowed to access SSH and serving APIs"
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(strcontains(var.my_external_ip, "/") ? var.my_external_ip : "${var.my_external_ip}/32", 0))
    error_message = "my_external_ip must be a valid IPv4 address (e.g. 1.2.3.4) or CIDR block (e.g. 0.0.0.0/0)."
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "region" {
  description = "The GCP Region to deploy resources"
  type        = string
  default     = "us-central1"
}

# GPU availability observed with:
# gcloud compute accelerator-types list \
#   --filter="name~'nvidia-l4|nvidia-tesla-t4'" \
#   --format="table(name,zone)"
#
# Change region and zones together. A regional MIG cannot span regions.
# L4:
#   us-central1: a,b,c       us-east1: b,c,d          us-east4: a,c
#   us-west1: a,b,c           us-west4: a,c            europe-west1: b,c
#   europe-west2: a,b         europe-west3: a,b        europe-west4: a,b,c
#   europe-west6: b,c         asia-east1: a,b,c        asia-east2: c
#   asia-northeast1: a,b,c    asia-northeast3: a,b     asia-southeast1: a,b,c
#   asia-south1: a,b,c        northamerica-northeast1: b,c
#   northamerica-northeast2: a,b  me-central2: a,c
# T4:
#   us-central1: a,b,c,f       us-east1: b,c,d          us-east4: a,b,c
#   us-west1: a,b               us-west4: a,b,c          europe-west1: b,c,d
#   europe-west2: a,b           europe-west3: b          europe-west4: a,b,c
#   asia-east1: a,b,c            asia-northeast1: a,c    asia-northeast3: b,c
#   asia-southeast1: a,b,c       asia-south1: a,b         asia-east2: a,c
#   australia-southeast1: a,c    northamerica-northeast1: c
#   southamerica-east1: a,b,c    me-west1: b,c
variable "zones" {
  description = "The specific zones in the region to distribute instances for capacity resilience"
  type        = list(string)
  default     = ["us-central1-a", "us-central1-b", "us-central1-c"]

  validation {
    condition     = alltrue([for zone in var.zones : startswith(zone, "${var.region}-")])
    error_message = "Every zone must belong to the selected region. Change region and zones together."
  }
}

variable "gpu_type" {
  description = "The type of GPU to deploy. Options: L4, T4"
  type        = string
  default     = "L4"
}

variable "is_spot" {
  description = "Whether to use Spot VMs to significantly reduce costs during learning"
  type        = bool
  default     = false
}

variable "target_size" {
  description = "The number of GPU instances to run in the MIG"
  type        = number
  default     = 1
}

locals {
  gpu_configs = {
    "L4" = {
      machine_type            = "g2-standard-12" # 48 GB RAM + 1x L4 GPU
      accelerator_type        = "nvidia-l4"
      accelerator_count       = 1
      supported_zone_suffixes = ["a", "b", "c"]
    }
    "T4" = {
      machine_type            = "n1-standard-8" # 30 GB RAM + 1x T4 GPU
      accelerator_type        = "nvidia-tesla-t4"
      accelerator_count       = 1
      supported_zone_suffixes = ["a", "b", "f"]
    }
  }

  selected_gpu = local.gpu_configs[var.gpu_type]

  # Change var.region and var.zones together when moving to another region.
  # The MIG itself remains regional; it cannot span multiple regions.
  eligible_zones = [
    for z in var.zones : z
    if contains(local.selected_gpu.supported_zone_suffixes, split("-", z)[length(split("-", z)) - 1])
  ]
}

# --- Use the existing default VPC and regional subnet ---
data "google_compute_network" "default" {
  name    = "default"
  project = var.project_id
}

data "google_compute_subnetwork" "default" {
  name    = "default"
  region  = var.region
  project = var.project_id
}


# Firewall pentru SSH
resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh-gpu"
  network = data.google_compute_network.default.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [strcontains(var.my_external_ip, "/") ? var.my_external_ip : "${var.my_external_ip}/32"]
}

resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "allow-iap-ssh-gpu"
  network = data.google_compute_network.default.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}


# Firewall pentru API ports (NIM / vLLM / Ollama)
resource "google_compute_firewall" "allow_serving_api" {
  name    = "allow-serving-api"
  network = data.google_compute_network.default.name

  allow {
    protocol = "tcp"
    ports    = ["8000", "11434", "4000"]
  }

  source_ranges = [strcontains(var.my_external_ip, "/") ? var.my_external_ip : "${var.my_external_ip}/32"]
}

# --- Instance Template ---
resource "google_compute_instance_template" "gpu_template" {
  name_prefix  = "gpu-instance-template-"
  machine_type = local.selected_gpu.machine_type
  region       = var.region

  disk {
    source_image = "ubuntu-os-cloud/ubuntu-2204-lts"
    auto_delete  = true
    boot         = true
    disk_size_gb = 150 # Spațiu generos pentru modele LLM pe care le vei descărca manual
    disk_type    = "pd-balanced"
  }

  guest_accelerator {
    type  = local.selected_gpu.accelerator_type
    count = local.selected_gpu.accelerator_count
  }

  network_interface {
    subnetwork = data.google_compute_subnetwork.default.id
    access_config {
      # Generează un IP public efemer ca să te poți conecta
    }
  }

  scheduling {
    on_host_maintenance = "TERMINATE"
    automatic_restart   = var.is_spot ? false : true
    preemptible         = var.is_spot
    provisioning_model  = var.is_spot ? "SPOT" : "STANDARD"
  }

  service_account {
    email  = var.compute_service_account_email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -euo pipefail

    exec > >(tee -a /var/log/gpu-startup-script.log | logger -t gpu-startup-script -s 2>/dev/console) 2>&1

    STATE_DIR="/var/lib/gpu-startup"
    mkdir -p "$STATE_DIR"

    # The driver installation needs one reboot; continue with Docker after it.
    if [[ ! -f "$STATE_DIR/driver-installed" ]]; then
      fallocate -l 32G /swapfile
      chmod 600 /swapfile
      mkswap /swapfile
      swapon /swapfile
      grep -q '^/swapfile none swap' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab

      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        nvidia-headless-550-server nvidia-utils-550-server

      touch "$STATE_DIR/driver-installed"
      reboot
    fi

    if [[ ! -f "$STATE_DIR/container-toolkit-installed" ]]; then
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg

      install -m 0755 -d /usr/share/keyrings
      curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
        | gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
      curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
        | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#' \
        > /etc/apt/sources.list.d/nvidia-container-toolkit.list

      curl -fsSL https://get.docker.com | sh
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-container-toolkit
      nvidia-ctk runtime configure --runtime=docker
      systemctl enable --now docker
      systemctl restart docker
      nvidia-smi -pm 1 || true

      mkdir -p /root/.cache/nim
      chmod 777 /root/.cache/nim
      touch "$STATE_DIR/container-toolkit-installed"
    fi
  EOT

  lifecycle {
    create_before_destroy = true
  }
}

# --- Managed Instance Group (MIG) ---
resource "google_compute_region_instance_group_manager" "gpu_mig" {
  name               = "gpu-regional-mig"
  base_instance_name = "gpu-worker"
  region             = var.region

  distribution_policy_zones        = local.eligible_zones
  distribution_policy_target_shape = "ANY" # Forțează MIG-ul să folosească orice zonă disponibilă dacă una este epuizată

  version {
    instance_template = google_compute_instance_template.gpu_template.id
  }

  target_size = var.target_size

  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_surge_fixed       = length(local.eligible_zones) # Setat egal cu numărul de zone eligibile
    max_unavailable_fixed = 0
  }
}
