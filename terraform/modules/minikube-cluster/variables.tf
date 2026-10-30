variable "cluster_name" {
  description = "Name used for the Minikube profile and Kubernetes context."
  type        = string

  validation {
    condition = (
      length(var.cluster_name) >= 3 &&
      length(var.cluster_name) <= 63 &&
      can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.cluster_name))
    )
    error_message = "cluster_name must be a lowercase DNS label between 3 and 63 characters."
  }
}

variable "driver" {
  description = "Minikube driver. TaskFlow supports Docker only for local and CI parity."
  type        = string

  validation {
    condition     = var.driver == "docker"
    error_message = "driver must be docker; privileged or host-level drivers are not supported."
  }
}

variable "kubernetes_version" {
  description = "Explicit Kubernetes version supported by the pinned Minikube release."
  type        = string

  validation {
    condition     = var.kubernetes_version == "v1.37.0"
    error_message = "kubernetes_version must be v1.37.0, the version verified for this module."
  }
}

variable "cpus" {
  description = "CPUs allocated to each Minikube node."
  type        = number

  validation {
    condition     = var.cpus >= 2 && var.cpus <= 8 && floor(var.cpus) == var.cpus
    error_message = "cpus must be a whole number between 2 and 8."
  }
}

variable "memory" {
  description = "Memory allocated to each Minikube node, in GiB."
  type        = number

  validation {
    condition     = var.memory >= 2 && var.memory <= 16 && floor(var.memory) == var.memory
    error_message = "memory must be a whole number between 2 and 16 GiB."
  }
}

variable "disk_size" {
  description = "Disk allocated to each Minikube node, in GiB."
  type        = number

  validation {
    condition     = var.disk_size >= 10 && var.disk_size <= 50 && floor(var.disk_size) == var.disk_size
    error_message = "disk_size must be a whole number between 10 and 50 GiB."
  }
}

variable "nodes" {
  description = "Number of Minikube nodes."
  type        = number

  validation {
    condition     = var.nodes >= 1 && var.nodes <= 3 && floor(var.nodes) == var.nodes
    error_message = "nodes must be a whole number between 1 and 3."
  }
}
