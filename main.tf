# main.tf
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.23.0"
    }
  }
}

provider "google" {
  credentials = file(var.credentials_file_path)
  project     = var.project_id
  region      = var.region
}

# VPC Configuration
resource "google_compute_network" "vpc" {
  name                    = "vpc-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "vpc-subnet"
  ip_cidr_range = "10.128.0.0/20"
  network       = google_compute_network.vpc.name
  region        = var.region
}

resource "google_compute_firewall" "allow-ssh-internal" {
  name          = "allow-ssh-internal"
  network       = google_compute_network.vpc.name
  source_ranges = ["0.0.0.0/0"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  priority = 1000
}

resource "google_compute_firewall" "deny-ssh-internal" {
  name          = "deny-ssh-internal"
  network       = google_compute_network.vpc.name
  source_ranges = ["10.128.0.101/32"]
  deny {
    protocol = "tcp"
    ports    = ["22"]
  }
  priority = 900
}

# Instance Template with External IP
resource "google_compute_instance_template" "ig-template" {
  name_prefix  = "auto-scaling-igt-"
  machine_type = "e2-micro"
  region       = var.region

  disk {
    auto_delete  = true
    boot         = true
    disk_size_gb = 10
    source_image = "debian-cloud/debian-11"
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.name
    access_config {}
  }
}

# Managed Instance Group
resource "google_compute_instance_group_manager" "mig" {
  name               = "auto-scaling-mig"
  base_instance_name = "vm"
  zone               = "${var.region}-a"
  target_size        = 2

  version {
    instance_template = google_compute_instance_template.ig-template.id
  }
}

# Autoscaler Configuration
resource "google_compute_autoscaler" "autoscaler" {
  name   = "mig-autoscaler"
  zone   = "${var.region}-a"
  target = google_compute_instance_group_manager.mig.id

  autoscaling_policy {
    min_replicas = 2
    max_replicas = 5
    cooldown_period = 60

    cpu_utilization {
      target = 0.6
    }
  }
}

# Standalone Test VMs
resource "google_compute_instance" "allowed-test-vm" {
  name         = "allowed-test-vm"
  machine_type = "e2-micro"
  zone         = "${var.region}-a"

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.name
    network_ip = "10.128.0.100"
    access_config {}
  }

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }
}

resource "google_compute_instance" "denied-test-vm" {
  name         = "denied-test-vm"
  machine_type = "e2-micro"
  zone         = "${var.region}-a"

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.name
    network_ip = "10.128.0.101"
    access_config {}
  }

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }
}