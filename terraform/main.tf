terraform {
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_compute_network" "vpc" {
  name                    = "iii-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "public" {
  name          = "iii-public-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

resource "google_compute_subnetwork" "private" {
  name                     = "iii-private-subnet"
  ip_cidr_range            = "10.0.1.0/24"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

resource "google_compute_router" "router" {
  name    = "iii-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "iii-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = google_compute_network.vpc.name
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gateway"]
}

resource "google_compute_firewall" "allow_http_api" {
  name    = "allow-iii-http"
  network = google_compute_network.vpc.name
  allow {
    protocol = "tcp"
    ports    = ["3111"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gateway"]
}

resource "google_compute_firewall" "allow_engine_internal" {
  name    = "allow-iii-engine-internal"
  network = google_compute_network.vpc.name
  allow {
    protocol = "tcp"
    ports    = ["49134"]
  }
  source_ranges = ["10.0.0.0/24", "10.0.1.0/24"]
  target_tags   = ["gateway"]
}

resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal"
  network = google_compute_network.vpc.name
  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }
  source_ranges = ["10.0.0.0/8"]
}

resource "google_compute_instance" "gateway" {
  name         = "iii-gateway"
  machine_type = "e2-small"
  zone         = var.zone
  tags         = ["gateway"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.public.id
    access_config {}
  }

  metadata = {
    ssh-keys       = "debian:${var.ssh_pub_key}"
    startup-script = file("${path.module}/../scripts/setup-gateway.sh")
  }
}

resource "google_compute_instance" "inference_worker" {
  name         = "iii-inference-worker"
  machine_type = "e2-standard-2"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 30
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.id
  }

  metadata = {
    ssh-keys       = "debian:${var.ssh_pub_key}"
    engine-ip      = google_compute_instance.gateway.network_interface[0].network_ip
    startup-script = file("${path.module}/../scripts/setup-inference-worker.sh")
  }

  depends_on = [google_compute_instance.gateway]
}

resource "google_compute_instance" "caller_worker" {
  name         = "iii-caller-worker"
  machine_type = "e2-small"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.id
  }

  metadata = {
    ssh-keys       = "debian:${var.ssh_pub_key}"
    engine-ip      = google_compute_instance.gateway.network_interface[0].network_ip
    startup-script = file("${path.module}/../scripts/setup-caller-worker.sh")
  }

  depends_on = [google_compute_instance.gateway]
}
