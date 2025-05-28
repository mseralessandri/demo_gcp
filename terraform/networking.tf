# =============================================================================
# NETWORKING CONFIGURATION FOR DR ACTIVE-PASSIVE COMPLETE ZONAL MODULE
# =============================================================================
# This file contains the networking resources for the DR solution, including
# load balancing, health checks, and instance groups.

# -----------------------------------------------------------------------------
# HEALTH CHECK
# -----------------------------------------------------------------------------
# Health check to monitor the application availability

resource "google_compute_health_check" "app_health_check" {
  name               = "app-health-check"
  timeout_sec        = 5
  check_interval_sec = 10
  
  http_health_check {
    port         = 8080
    request_path = "/web"
  }
}

# -----------------------------------------------------------------------------
# INSTANCE GROUPS
# -----------------------------------------------------------------------------
# Instance groups for the primary and standby VMs

# Primary instance group
resource "google_compute_instance_group" "primary_group" {
  name      = "app-primary-group"
  zone      = var.primary_zone
  instances = [google_compute_instance.primary_vm.id]
  
  named_port {
    name = "http8080"
    port = 8080
  }
  
  # Prevent Terraform from trying to update the instance group if the VM is stopped
  lifecycle {
    ignore_changes = [instances]
  }
}

# Standby instance group (empty by default)
resource "google_compute_instance_group" "standby_group" {
  name      = "app-standby-group"
  zone      = var.standby_zone
  instances = []  # Empty by default, will be populated during failover
  
  named_port {
    name = "http8080"
    port = 8080
  }
  
  # Ensure named ports are preserved even when instances change
  lifecycle {
    ignore_changes = [instances]
  }
}

# -----------------------------------------------------------------------------
# LOAD BALANCING
# -----------------------------------------------------------------------------
# Load balancer to route traffic to the active instance

# Backend service
resource "google_compute_backend_service" "app_backend" {
  name          = "app-backend-service"
  health_checks = [google_compute_health_check.app_health_check.id]
  port_name     = "http8080"
  
  backend {
    group = google_compute_instance_group.primary_group.id
    balancing_mode = "UTILIZATION"
    capacity_scaler = 1.0
  }
  
  backend {
    group = google_compute_instance_group.standby_group.id
    balancing_mode = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

# URL map
resource "google_compute_url_map" "app_url_map" {
  name            = "app-url-map"
  default_service = google_compute_backend_service.app_backend.id
}

# Self-signed SSL certificate
resource "google_compute_ssl_certificate" "app_ssl_cert" {
  name        = var.ssl_certificate_name
  private_key = file("${path.module}/${var.ssl_private_key_path}")
  certificate = file("${path.module}/${var.ssl_certificate_path}")
  
  lifecycle {
    create_before_destroy = true
  }
}

# HTTP proxy
resource "google_compute_target_http_proxy" "app_http_proxy" {
  name    = "app-http-proxy"
  url_map = google_compute_url_map.app_url_map.id
}

# HTTPS proxy
resource "google_compute_target_https_proxy" "app_https_proxy" {
  name             = "app-https-proxy"
  url_map          = google_compute_url_map.app_url_map.id
  ssl_certificates = [google_compute_ssl_certificate.app_ssl_cert.id]
}

# Static IP address for the load balancer
resource "google_compute_global_address" "app_lb_ip" {
  name = "app-lb-ip"
}

# HTTP forwarding rule
resource "google_compute_global_forwarding_rule" "app_http_forwarding_rule" {
  name       = "app-http-forwarding-rule"
  target     = google_compute_target_http_proxy.app_http_proxy.id
  port_range = "80"
  ip_address = google_compute_global_address.app_lb_ip.address
}

# HTTPS forwarding rule
resource "google_compute_global_forwarding_rule" "app_https_forwarding_rule" {
  name       = "app-https-forwarding-rule"
  target     = google_compute_target_https_proxy.app_https_proxy.id
  port_range = "443"
  ip_address = google_compute_global_address.app_lb_ip.address
}

# -----------------------------------------------------------------------------
# FIREWALL RULES
# -----------------------------------------------------------------------------
# Firewall rules to allow traffic to the VMs

# Allow HTTP, HTTPS, and application traffic
resource "google_compute_firewall" "allow_http" {
  name    = "allow-http-dr"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]
}

# Allow SSH traffic through Identity-Aware Proxy (IAP) only
resource "google_compute_firewall" "allow_ssh_iap" {
  name    = "allow-ssh-iap-dr"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP IP range for secure SSH tunneling
  source_ranges = var.iap_source_ranges
  target_tags   = ["web"]
}

# Allow health checks
resource "google_compute_firewall" "allow_health_checks" {
  name    = "allow-health-checks-dr"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = var.health_check_source_ranges
  target_tags   = ["web"]
}
