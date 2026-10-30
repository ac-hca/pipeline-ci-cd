module "minikube_cluster" {
  source = "../../modules/minikube-cluster"

  cluster_name       = var.cluster_name
  driver             = var.driver
  kubernetes_version = var.kubernetes_version
  cpus               = var.cpus
  memory             = var.memory
  disk_size          = var.disk_size
  nodes              = var.nodes
}
