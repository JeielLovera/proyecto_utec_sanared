# =============================================================================
# Red GCP — VPC de imágenes + analítica (ADR-A3M-001). Modo custom (sin subredes
# automáticas) para controlar el CIDR y no solapar con AWS/Azure.
# =============================================================================
resource "google_compute_network" "empi" {
  name                    = "${local.name_prefix}-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.this]
}

resource "google_compute_subnetwork" "empi" {
  name          = "${local.name_prefix}-subnet"
  network       = google_compute_network.empi.id
  ip_cidr_range = var.vpc_cidr
  region        = var.region

  # Necesario para que Cloud Run (conector VPC) y servicios privados usen rango interno.
  private_ip_google_access = true
}

# Conector VPC Access — permite que Cloud Run (serverless) hable con la VPN privada.
resource "google_vpc_access_connector" "empi" {
  name          = "${substr(local.name_prefix, 0, 18)}-conn" # <=25 chars
  region        = var.region
  network       = google_compute_network.empi.name
  ip_cidr_range = cidrsubnet(var.vpc_cidr, 8, 8) # /24 dedicado al conector
  depends_on    = [google_project_service.this]
}

# --- Firewall: permite tráfico interno + desde AWS (por la VPN, stack 40) ---
resource "google_compute_firewall" "internal" {
  name    = "${local.name_prefix}-allow-internal"
  network = google_compute_network.empi.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [var.vpc_cidr]
}

resource "google_compute_firewall" "from_aws" {
  name    = "${local.name_prefix}-allow-from-aws"
  network = google_compute_network.empi.name

  allow {
    protocol = "tcp"
  }

  # Tráfico proveniente del bus MSK (AWS) por el túnel VPN (stack 40).
  source_ranges = [var.aws_cidr]
}
