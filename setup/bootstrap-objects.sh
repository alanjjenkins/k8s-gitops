#!/bin/bash

REPO_ROOT=$(git rev-parse --show-toplevel)

need() {
    which "$1" &>/dev/null || die "Binary '$1' is missing but required"
}

need "kubectl"

message() {
  echo -e "\n######################################################################"
  echo "# $1"
  echo "######################################################################"
}

kapply() {
  if output=$(envsubst < "$@"); then
    printf '%s' "$output" | kubectl apply -f -
  fi
}

installManualObjects(){
  . "$REPO_ROOT"/setup/.env

  message "installing manual secrets and objects"

  ##########
  # secrets
  ##########
  kubectl --namespace kube-system create secret generic kms-vault --from-literal=account.json="$(echo $VAULT_KMS_ACCOUNT_JSON | base64 --decode)"

  ###################
  # nginx
  ###################
  for i in "$REPO_ROOT"/kube-system/nginx/nginx-external/*.txt
  do
    kapply "$i"
  done

  kapply "$REPO_ROOT"/default/frigate/frigate-noauth-ingress.txt

  ###################
  # rook
  ###################
  ROOK_NAMESPACE_READY=1
  while [ $ROOK_NAMESPACE_READY != 0 ]; do
    echo "waiting for rook-ceph namespace to be fully ready..."
    # this is a hack to check for the namespace
    kubectl --namespace rook-ceph wait --for condition=Established crd/volumes.rook.io > /dev/null 2>&1
    ROOK_NAMESPACE_READY="$?"
    sleep 5
  done
  kapply "$REPO_ROOT"/rook-ceph/dashboard/ingress.txt

  #########################
  # cert-manager bootstrap
  #########################
  CERT_MANAGER_READY=1
  while [ $CERT_MANAGER_READY != 0 ]; do
    echo "waiting for cert-manager to be fully ready..."
    kubectl --namespace cert-manager wait --for condition=Available deployment/cert-manager > /dev/null 2>&1
    CERT_MANAGER_READY="$?"
    sleep 5
  done
  kapply "$REPO_ROOT"/cert-manager/cloudflare/cert-manager-letsencrypt.txt

}

installManualObjects

message "all done!"
