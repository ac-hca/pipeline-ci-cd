terraform {
  required_version = "= 1.16.7"

  required_providers {
    minikube = {
      source  = "scott-the-programmer/minikube"
      version = "= 0.8.0"
    }
  }
}

provider "minikube" {
  kubernetes_version = var.kubernetes_version
}
