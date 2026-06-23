resource "kubernetes_namespace" "database" {
  metadata {
    name = "database"
  }
}

resource "kubernetes_deployment" "postgres" {
  metadata {
    name      = "postgres-db"
    namespace = kubernetes_namespace.database.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "postgres-db"
      }
    }

    template {
      metadata {
        labels = {
          app = "postgres-db"
        }
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:16"

          env {
            name  = "POSTGRES_DB"
            value = "appdb"
          }
          env {
            name  = "POSTGRES_USER"
            value = "postgres"
          }
          env {
            name  = "POSTGRES_PASSWORD"
            value = "devpassword"
          }

          port {
            container_port = 5432
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "postgres" {
  metadata {
    name      = "postgres-db"
    namespace = kubernetes_namespace.database.metadata[0].name
  }

  spec {
    selector = {
      app = "postgres-db"
    }

    port {
      port        = 5432
      target_port = 5432
    }

    type = "ClusterIP"
  }
}
