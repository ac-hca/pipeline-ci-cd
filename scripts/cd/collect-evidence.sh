#!/usr/bin/env bash

set -euo pipefail

evidence_dir="${EVIDENCE_DIR:-./delivery-evidence}"
cluster_context="${KUBERNETES_CONTEXT:-taskflow-development}"
namespace="${TASKFLOW_NAMESPACE:-taskflow-development}"
terraform_dir="${TERRAFORM_DIR:-terraform/environments/development}"
delivered_image="${DELIVERED_IMAGE_REF:-unknown}"

mkdir -p "$evidence_dir"

capture() {
  local filename="$1"
  shift

  if ! "$@" >"$evidence_dir/$filename" 2>&1; then
    printf '\nCommand failed while collecting this diagnostic.\n' >>"$evidence_dir/$filename"
  fi
}

{
  echo "Collected at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Requested image: $delivered_image"
  echo "Kubernetes context: $cluster_context"
  echo "Namespace: $namespace"
  echo
  terraform version | head -n 1 || true
  minikube version --short || true
  kubectl version --client || true
  helm version --short || true
  docker version --format 'Docker client {{.Client.Version}}; server {{.Server.Version}}' || true
} >"$evidence_dir/tool-versions.txt" 2>&1

capture cluster-info.txt kubectl --context "$cluster_context" cluster-info
capture nodes.txt kubectl --context "$cluster_context" get nodes -o wide
capture namespaces.txt kubectl --context "$cluster_context" get namespaces
capture workload-overview.txt kubectl --context "$cluster_context" -n "$namespace" get all -o wide
capture ingress.txt kubectl --context "$cluster_context" -n "$namespace" get ingress -o wide
capture hpa.txt kubectl --context "$cluster_context" -n "$namespace" get hpa
capture pdb.txt kubectl --context "$cluster_context" -n "$namespace" get pdb
capture pvc.txt kubectl --context "$cluster_context" -n "$namespace" get pvc
capture events.txt kubectl --context "$cluster_context" -n "$namespace" get events --sort-by=.metadata.creationTimestamp
capture api-description.txt kubectl --context "$cluster_context" -n "$namespace" describe deployment taskflow-api
capture postgres-description.txt kubectl --context "$cluster_context" -n "$namespace" describe statefulset taskflow-postgres
capture migration-description-final.txt kubectl --context "$cluster_context" -n "$namespace" describe job taskflow-migrate
capture api-logs.txt kubectl --context "$cluster_context" -n "$namespace" logs deployment/taskflow-api --all-containers --prefix
capture postgres-logs.txt kubectl --context "$cluster_context" -n "$namespace" logs statefulset/taskflow-postgres --all-containers --prefix
capture migration-logs-final.txt kubectl --context "$cluster_context" -n "$namespace" logs job/taskflow-migrate --all-containers --prefix
capture metrics.txt kubectl --context "$cluster_context" top pods -n "$namespace"
capture helm-releases.txt helm list --all-namespaces --kube-context "$cluster_context"
capture terraform-outputs.json terraform -chdir="$terraform_dir" output -json

capture deployed-image.txt kubectl \
  --context "$cluster_context" \
  -n "$namespace" \
  get deployment taskflow-api \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="api")].image}{"\n"}'
