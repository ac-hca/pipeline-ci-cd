output "cluster_name" {
  description = "Minikube profile name."
  value       = module.minikube_cluster.cluster_name
}

output "kubernetes_context" {
  description = "Kubernetes context created by Minikube."
  value       = module.minikube_cluster.kubernetes_context
}

output "cluster_api_endpoint" {
  description = "Non-sensitive Kubernetes API endpoint used to verify connectivity."
  value       = module.minikube_cluster.cluster_api_endpoint
}

output "verification_command" {
  description = "Command that verifies the node state without changing the active context."
  value       = module.minikube_cluster.verification_command
}
