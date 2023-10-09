#Create bucket for website files
resource "google_storage_bucket" "website" {
    name = "website-bucket-terraform"
    location = var.gcp_region
    #Uncomment the following after creating the bucket
    # website {
    #     main_page_suffix = "index.html"
    #     not_found_page = "404.html"
    # }
}

#Upload index.html to bucket
resource "google_storage_bucket_object" "file_src_index" {
    name = "index.html"
    bucket = google_storage_bucket.website.name
    source = "files/index.html"
    content_type = "text/html"
    #add mainpage surfix
}
#Upload 404.html to bucket
resource "google_storage_bucket_object" "file_src_404" {
    name = "404.html"
    bucket = google_storage_bucket.website.name
    source = "files/404.html"
    content_type = "text/html"
    #add 404 surfix
}
#Upload style.css to bucket
resource "google_storage_bucket_object" "file_src_style" {
    name = "style.css"
    bucket = google_storage_bucket.website.name
    source = "files/style.css"
    content_type = "text/css"
    #add css surfix
}

#Make index.html public in bucket
resource "google_storage_object_access_control" "public_rule_index" {
    bucket = google_storage_bucket.website.name
    object = google_storage_bucket_object.file_src_index.name
    role = "READER"
    entity = "allUsers"
}
#Make 404.html public in bucket
resource "google_storage_object_access_control" "public_rule_404" {
    bucket = google_storage_bucket.website.name
    object = google_storage_bucket_object.file_src_404.name
    role = "READER"
    entity = "allUsers"
}
#Make style.css public in bucket
resource "google_storage_object_access_control" "public_rule_style" {
    bucket = google_storage_bucket.website.name
    object = google_storage_bucket_object.file_src_style.name
    role = "READER"
    entity = "allUsers"
}

#Reserve static IP for website load balancer
resource "google_compute_global_address" "website_ip" {
    name = "website-ip"
}

#Get the managed zone and save for later use
data "google_dns_managed_zone" "website_zone" {
    name = var.gcp_dns_zone
}

#Add IP to DNS record (Adding A type record to DNS)
resource "google_dns_record_set" "website_dns" {
    name = "${var.gcp_subdomain}.${data.google_dns_managed_zone.website_zone.dns_name}"
    managed_zone = data.google_dns_managed_zone.website_zone.name
    type = "A"
    ttl = 300
    rrdatas = [google_compute_global_address.website_ip.address]
}

#Add bucket to Cloud Delivery Network (CDN)
resource "google_compute_backend_bucket" "website_bucket" {
    name = "website-bucket"
    bucket_name = google_storage_bucket.website.name
    enable_cdn = true
}

#Create basic URL map
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

######################
#                    #
#Enable HTTP redirect#
#                    #
######################
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
######################
#                    #
#End of HTTP Redirect#
#                    #
######################

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
