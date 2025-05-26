# Cloud Storage
# resource "google_storage_bucket" "db" {
#   name     = "todoapp-db"
#   location = "asia-northeast1"
# }

# Artifact Registry
resource "google_project_service" "artifact_registry" {
  service = "artifactregistry.googleapis.com"
}

resource "google_artifact_registry_repository" "main" {
  depends_on = [google_project_service.artifact_registry]

  location      = "asia-northeast1"
  repository_id = var.project
  format        = "DOCKER"
}

# IAM for the application service account
locals {
  app_roles = ["roles/storage.admin"]
}

resource "google_service_account" "app" {
  account_id = "${var.project}-app"
}

resource "google_project_iam_member" "app" {
  for_each = toset(local.app_roles)

  project = var.project
  role    = each.value
  member  = "serviceAccount:${google_service_account.app.email}"
}

# Cloud Run
locals {
  services = [
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
  ]
}

resource "google_project_service" "main" {
  for_each = toset(local.services)

  service = each.value
}

resource "google_cloud_run_v2_service" "main" {
  depends_on = [google_project_service.main]

  name     = google_artifact_registry_repository.main.name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.app.email

    scaling {
      max_instance_count = 1
    }

    containers {
      image = "${google_artifact_registry_repository.main.location}-docker.pkg.dev/${var.project}/${google_artifact_registry_repository.main.name}/app:latest"
      ports {
        container_port = 8080
      }
    }
  }
}

data "google_iam_role" "run_invoker" {
  name = "roles/run.invoker"
}

data "google_iam_policy" "cloud_run_noauth" {
  binding {
    role    = data.google_iam_role.run_invoker.name
    members = ["allUsers"]
  }
}

resource "google_cloud_run_service_iam_policy" "cloud_run_noauth" {
  location    = google_cloud_run_v2_service.main.location
  project     = google_cloud_run_v2_service.main.project
  service     = google_cloud_run_v2_service.main.name
  policy_data = data.google_iam_policy.cloud_run_noauth.policy_data
}

output "url" {
  value = google_cloud_run_v2_service.main.uri
}
