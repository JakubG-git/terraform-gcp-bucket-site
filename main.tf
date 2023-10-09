#Bucket for website
resource "google_storage_bucket" "website" {
    name = "website-bucket-terraform"
    location = var.gcp_region
}

#Make files public
resource "google_storage_object_access_control" "public_rule" {
    bucket = google_storage_bucket.website.name
    object = google_storage_bucket_object.file_src.name
    role = "READER"
    entity = "allUsers"
}

#Website files
resource "google_storage_bucket_object" "file_src" {
    name = "index.html"
    bucket = google_storage_bucket.website.name
    source = "index.html"
    content_type = "text/html"
}

#Reserve static IP
resource "google_compute_global_address" "website_ip" {
    name = "website-ip"
}

#Get the managed zone
data "google_dns_managed_zone" "website_zone" {
    name = var.gcp_dns_zone
}

#Add IP to DNS
resource "google_dns_record_set" "website_dns" {
    name = "${var.gcp_subdomain}.${data.google_dns_managed_zone.website_zone.dns_name}"
    managed_zone = data.google_dns_managed_zone.website_zone.name
    type = "A"
    ttl = 300
    rrdatas = [google_compute_global_address.website_ip.address]
}

#Add bucket to CDN
resource "google_compute_backend_bucket" "website_bucket" {
    name = "website-bucket"
    bucket_name = google_storage_bucket.website.name
    enable_cdn = true
}

#GCP url map
resource "google_compute_url_map" "website_map" {
    name = "website-map"
    default_service = google_compute_backend_bucket.website_bucket.self_link
    host_rule {
        hosts = ["${var.gcp_subdomain}.${data.google_dns_managed_zone.website_zone.dns_name}"]
        path_matcher = "allpaths"
    }
    path_matcher {
        name = "allpaths"
        default_service = google_compute_backend_bucket.website_bucket.self_link
        path_rule {
            paths = ["/"]
            service = google_compute_backend_bucket.website_bucket.self_link
        }
    }
}
#HTTP redirect
resource "google_compute_url_map" "http-redirect" {
  name = "http-redirect"

  default_url_redirect {
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"  // 301 redirect
    strip_query            = false
    https_redirect         = true  // this is the magic
  }
}
#HTTP proxy
resource "google_compute_target_http_proxy" "http-redirect" {
  name    = "http-redirect"
  url_map = google_compute_url_map.http-redirect.self_link
}
#HTTP forwarding rule
resource "google_compute_global_forwarding_rule" "http-redirect" {
  name       = "http-redirect"
  target     = google_compute_target_http_proxy.http-redirect.self_link
  ip_address = google_compute_global_address.website_ip.address
  port_range = "80"
}

#SSL certificate
resource "google_compute_managed_ssl_certificate" "website_cert" {
    name = "website-cert"
    managed {
        domains = [google_dns_record_set.website_dns.name]
    }
}

#HTTPS proxy
resource "google_compute_target_https_proxy" "website_proxy" {
    name = "website-proxy"
    ssl_certificates = [google_compute_managed_ssl_certificate.website_cert.self_link]
    url_map = google_compute_url_map.website_map.self_link
}

#Create a load balancer
resource "google_compute_global_forwarding_rule" "website_lb" {
    name = "website-lb"
    target = google_compute_target_https_proxy.website_proxy.self_link
    port_range = "443"
    ip_protocol = "TCP"
    ip_address = google_compute_global_address.website_ip.address
    load_balancing_scheme = "EXTERNAL"
    
}
