terraform {
  required_version = ">= 1.3.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0.0"
    }
  }
}

variable "project_id" {
  description = "GCP Project ID for deployment"
  type        = string
}

variable "region" {
  description = "The GCP Region to deploy resources"
  type        = string
  default     = "us-central1" 
}

variable "zone" {
  description = "The specific zone to deploy the standalone VM"
  type        = string
  default     = "us-central1-a" 
}

variable "gpu_type" {
  description = "The type of GPU to deploy. Options: L4, T4"
  type        = string
  default     = "L4" 
}

variable "is_spot" {
  description = "Whether to use Spot VMs to significantly reduce costs during learning"
  type        = bool
  default     = true
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  gpu_configs = {
    "L4" = {
      machine_type      = "g2-standard-8" # 32 GB RAM + 1x L4 GPU
      accelerator_type  = "nvidia-l4"
      accelerator_count = 1
    }
    "T4" = {
      machine_type      = "n1-standard-8" # 30 GB RAM + 1x T4 GPU
      accelerator_type  = "nvidia-tesla-t4"
      accelerator_count = 1
    }
  }

  selected_gpu = local.gpu_configs[var.gpu_type]
}

# --- VPC & Networking Setup ---
resource "google_compute_network" "vpc_network" {
  name                    = "gpu-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "gpu-subnet"
  ip_cidr_range = "10.10.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc_network.id
}

# Firewall pentru SSH
resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh-gpu"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# Firewall pentru API ports (NIM / vLLM / Ollama)
resource "google_compute_firewall" "allow_serving_api" {
  name    = "allow-serving-api"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["8000", "11434"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# --- Standalone Instance ---
resource "google_compute_instance" "gpu_instance" {
  name         = "gpu-playground"
  machine_type = local.selected_gpu.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts" # <--- UPDATED: Ubuntu 24.04 LTS
      size  = 100                               # <--- UPDATED: 100 GB Size
      type  = "pd-balanced"
    }
  }

  guest_accelerator {
    type  = local.selected_gpu.accelerator_type
    count = local.selected_gpu.accelerator_count
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    access_config {
      # Public ephemeral IP
    }
  }

  scheduling {
    on_host_maintenance = "TERMINATE" 
    automatic_restart   = var.is_spot ? false : true
    preemptible         = var.is_spot
    provisioning_model  = var.is_spot ? "SPOT" : "STANDARD"
  }

  service_account {
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}
