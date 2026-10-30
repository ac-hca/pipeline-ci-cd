output "cluster_name" {
  description = "Minikube profile name."
  value       = minikube_cluster.this.cluster_name
}

output "kubernetes_context" {
  description = "Kubernetes context created by Minikube."
  value       = minikube_cluster.this.cluster_name
}

output "cluster_api_endpoint" {
  description = "Non-sensitive Kubernetes API endpoint used to verify connectivity."
  value       = minikube_cluster.this.host
}

output "verification_command" {
  description = "Command that verifies the node state without changing the active context."
  value       = "kubectl --context ${minikube_cluster.this.cluster_name} get nodes"
}
