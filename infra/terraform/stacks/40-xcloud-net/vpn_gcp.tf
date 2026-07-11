# =============================================================================
# VPN IPSec site-to-site AWS <-> GCP (segundo consumidor cross-cloud del bus, §6).
# Perfil DEMO: Classic VPN de GCP con rutas estáticas (mismo patrón que el túnel a
# Azure: simetría, sin BGP). Producción escalaría a HA VPN con Cloud Router/BGP.
# Reutiliza el mismo AWS VPN Gateway (aws_vpn_gateway.vgw, definido en vpn.tf) —
# una VGW admite múltiples Customer Gateways/conexiones a distintos sitios remotos.
# =============================================================================
locals {
  gcp_network_name = data.terraform_remote_state.gcp.outputs.network_name
  gcp_region       = data.terraform_remote_state.gcp.outputs.region
}

# ---------------------------------------------------------------------------
# GCP — IP estática + gateway VPN clásico + forwarding rules ESP/UDP500/UDP4500
# ---------------------------------------------------------------------------
resource "google_compute_address" "vpn" {
  name   = "${var.project}-${var.environment}-vpn-ip"
  region = local.gcp_region
}

resource "google_compute_vpn_gateway" "aws" {
  name    = "${var.project}-${var.environment}-vpngw"
  network = local.gcp_network_name
  region  = local.gcp_region
}

resource "google_compute_forwarding_rule" "esp" {
  name        = "${var.project}-${var.environment}-fr-esp"
  ip_protocol = "ESP"
  ip_address  = google_compute_address.vpn.address
  target      = google_compute_vpn_gateway.aws.id
  region      = local.gcp_region
}

resource "google_compute_forwarding_rule" "udp500" {
  name        = "${var.project}-${var.environment}-fr-udp500"
  ip_protocol = "UDP"
  port_range  = "500"
  ip_address  = google_compute_address.vpn.address
  target      = google_compute_vpn_gateway.aws.id
  region      = local.gcp_region
}

resource "google_compute_forwarding_rule" "udp4500" {
  name        = "${var.project}-${var.environment}-fr-udp4500"
  ip_protocol = "UDP"
  port_range  = "4500"
  ip_address  = google_compute_address.vpn.address
  target      = google_compute_vpn_gateway.aws.id
  region      = local.gcp_region
}

# ---------------------------------------------------------------------------
# AWS — segundo Customer Gateway (apunta a la IP estática de GCP) + conexión
# ---------------------------------------------------------------------------
resource "aws_customer_gateway" "gcp" {
  bgp_asn    = 65000
  ip_address = google_compute_address.vpn.address
  type       = "ipsec.1"
  tags       = { Name = "${var.project}-${var.environment}-cgw-gcp" }
}

resource "aws_vpn_connection" "to_gcp" {
  vpn_gateway_id        = aws_vpn_gateway.vgw.id
  customer_gateway_id   = aws_customer_gateway.gcp.id
  type                  = "ipsec.1"
  static_routes_only    = true
  tunnel1_preshared_key = var.shared_key_gcp
  tags                  = { Name = "${var.project}-${var.environment}-vpn-gcp" }
}

resource "aws_vpn_connection_route" "gcp" {
  destination_cidr_block = var.gcp_vpc_cidr
  vpn_connection_id      = aws_vpn_connection.to_gcp.id
}
# Nota: la propagación de rutas (aws_vpn_gateway_route_propagation.private, vpn.tf) ya
# cubre TODAS las conexiones adjuntas a aws_vpn_gateway.vgw — no se repite aquí.

# ---------------------------------------------------------------------------
# GCP — túnel VPN hacia AWS (peer = IP del túnel 1 de la conexión AWS) + ruta estática
# ---------------------------------------------------------------------------
resource "google_compute_vpn_tunnel" "aws" {
  name                    = "${var.project}-${var.environment}-tun-aws"
  region                  = local.gcp_region
  target_vpn_gateway      = google_compute_vpn_gateway.aws.id
  peer_ip                 = aws_vpn_connection.to_gcp.tunnel1_address
  shared_secret           = var.shared_key_gcp
  local_traffic_selector  = ["0.0.0.0/0"]
  remote_traffic_selector = ["0.0.0.0/0"]

  depends_on = [
    google_compute_forwarding_rule.esp,
    google_compute_forwarding_rule.udp500,
    google_compute_forwarding_rule.udp4500,
  ]
}

resource "google_compute_route" "to_aws" {
  name                = "${var.project}-${var.environment}-route-aws"
  network             = local.gcp_network_name
  dest_range          = data.terraform_remote_state.aws.outputs.vpc_cidr
  priority            = 1000
  next_hop_vpn_tunnel = google_compute_vpn_tunnel.aws.id
}
