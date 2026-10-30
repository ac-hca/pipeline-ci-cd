resource "minikube_cluster" "this" {
  cluster_name       = var.cluster_name
  driver             = var.driver
  kubernetes_version = var.kubernetes_version
  cpus               = tostring(var.cpus)
  memory             = format("%dmb", var.memory * 1024)
  disk_size          = format("%dmb", var.disk_size * 1024)
  nodes              = var.nodes

  addons = [
    "default-storageclass",
    "storage-provisioner",
  ]

  auto_update_drivers = false
  cni                 = "bridge"
  container_runtime   = "containerd"
  delete_on_failure   = true
  embed_certs         = false
  install_addons      = false
  interactive         = false
  keep_context        = true
  vm                  = false

  wait = [
    "apiserver",
    "node_ready",
    "system_pods",
  ]
  wait_timeout = 10

  lifecycle {
    precondition {
      condition     = var.cpus * var.nodes <= 8
      error_message = "The cluster may allocate at most 8 CPUs across all nodes."
    }

    precondition {
      condition     = var.memory * var.nodes <= 16
      error_message = "The cluster may allocate at most 16 GiB of memory across all nodes."
    }

    precondition {
      condition     = var.disk_size * var.nodes <= 60
      error_message = "The cluster may allocate at most 60 GiB of disk across all nodes."
    }
  }
}
