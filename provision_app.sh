#!/bin/bash

# This script provisions a project-specific namespace and associated deployment account for use with CI/CD. Optionally,
# a wildcard certificate is provisioned for a project-specific DNS zone.
#
# It is expected that the script will be executed while the working directory corresponds to the subscription-level
# terraform file (for example, from inside the icmus-dev folder).
set -e
set -o pipefail

NAMESPACE="$1"
DNS_ZONE_NAME="$2"
ACCOUNT="deploy"
CLUSTER_ROLE="admin"

# Validate arguments.
if [[ -z "$NAMESPACE" ]]; then
    echo "Usage: $0 <namespace> [dns_zone_name]"
    exit -1
fi

# Create namespace.
kubectl create ns "${NAMESPACE}" || true
kubectl label namespace "${NAMESPACE}" "name=${NAMESPACE}" || true

# This big ball of ugliness generates a kubeconfig file for use in the CI/CD pipeline. The service account has edit
# access only to the project's namespace.
mkdir -p ./out
TMP_PATH="$(mktemp -d)"
KUBECONFIG_OUT="./out/kubeconfig-${NAMESPACE}-${ACCOUNT}.yaml"
kubectl create sa "${ACCOUNT}" --namespace "${NAMESPACE}" || true
SECRET_NAME=$(kubectl get sa "${ACCOUNT}" --namespace "${NAMESPACE}" -o jsonpath="{.secrets[0].name}")
kubectl get secret --namespace "${NAMESPACE}" "${SECRET_NAME}" -o jsonpath="{.data['ca\.crt']}" |base64 --decode > "${TMP_PATH}/ca.crt"
USER_TOKEN=$(kubectl get secret --namespace "${NAMESPACE}" "${SECRET_NAME}" -o jsonpath="{.data['token']}" |base64 --decode)
CONTEXT=$(kubectl config current-context)
CLUSTER_NAME=$(kubectl config get-contexts "$CONTEXT" |awk '{print $3}' |tail -n 1)
ENDPOINT=$(kubectl config view -o jsonpath="{.clusters[?(@.name == \"${CLUSTER_NAME}\")].cluster.server}")
kubectl config set-cluster "${CLUSTER_NAME}" --kubeconfig="${KUBECONFIG_OUT}" \
    --server="${ENDPOINT}" --certificate-authority="${TMP_PATH}/ca.crt" --embed-certs=true
TRIPLET="${ACCOUNT}-${NAMESPACE}-${CLUSTER_NAME}"
kubectl config set-credentials "${TRIPLET}" --kubeconfig="${KUBECONFIG_OUT}" --token="${USER_TOKEN}"
kubectl config set-context "${TRIPLET}" --kubeconfig="${KUBECONFIG_OUT}" --cluster="${CLUSTER_NAME}" \
    --user="${TRIPLET}" --namespace="${NAMESPACE}"
kubectl config use-context "${TRIPLET}" --kubeconfig="${KUBECONFIG_OUT}"
kubectl create rolebinding "${ACCOUNT}" --namespace "${NAMESPACE}" --clusterrole "${CLUSTER_ROLE}" --serviceaccount "${NAMESPACE}:${ACCOUNT}"
echo "Deployment config written to ${KUBECONFIG_OUT}"
rm -rf ${TMP_PATH}

# If a DNS zone is specified, create a wildcard certificate object for the zone. The cert will be automatically
# requested via the Let's Encrypt certificate issuer (using cert-manager).
if [[ ! -z "$DNS_ZONE_NAME" ]]; then
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1alpha2
kind: Certificate
metadata:
  name: app-wildcard
  namespace: $NAMESPACE
spec:
  secretName: app-wildcard-tls
  duration: 2160h
  renewBefore: 360h
  commonName: $DNS_ZONE_NAME
  dnsNames:
  - $DNS_ZONE_NAME
  - '*.$DNS_ZONE_NAME'
  issuerRef:
    name: letsencrypt
    kind: ClusterIssuer
EOF
fi
