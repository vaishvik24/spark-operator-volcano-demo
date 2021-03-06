#!/usr/bin/env bash

# Copyright 2019 The Knative Authors.

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


set -o errexit
set -o nounset
set -o pipefail

export CURRENT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/..

function check-prerequisites {
  echo "checking prerequisites....."
  echo "checking go environment"
  if hash go 2>/dev/null; then
    echo -n "found go, " && go version
  else
    echo "go not installed, exiting."
    exit 1
  fi

  if [[ "${GOPATH}" == "" ]]; then
    echo "GOPATH not set, exiting."
    exit 1
  fi

  echo "checking kubectl"
  if hash kubectl 2>/dev/null; then
    echo -n "found kubectl, " && kubectl version --short --client
  else
    echo "kubectl not installed, exiting."
    exit 1
  fi

  echo "checking docker"
  if hash docker 2>/dev/null; then
    echo -n "found docker, version: " && docker version
  else
     echo "docker not installed, exiting."
    exit 1
  fi

  echo "checking kind"
  if hash kind 2>/dev/null; then
    echo -n "found kind, version: " && kind version
  else
    echo "installing kind ."
    GO111MODULE="on" go get sigs.k8s.io/kind@v0.4.0
    export PATH=${GOPATH}/bin:${GOROOT}/bin:${PATH}
  fi
}

function kind-cluster-up {
    echo "Installing kind cluster named with integration...."
    kind create cluster --config "${CURRENT_DIR}/hack/kind-config.yaml" --name "integration"  --wait "200s"
}

function install-helm {
  echo "checking helm"
  if hash helm 2>/dev/null; then
    echo "found helm on local"
  else
    echo "Install helm via script"
    HELM_TEMP_DIR=`mktemp -d`
    curl https://raw.githubusercontent.com/helm/helm/master/scripts/get > ${HELM_TEMP_DIR}/get_helm.sh
    #TODO: There are some issue with helm's latest version, remove '--version' when it get fixed.
    chmod 700 ${HELM_TEMP_DIR}/get_helm.sh && ${HELM_TEMP_DIR}/get_helm.sh   --version v2.13.0
  fi
  echo "installing helm tiller service"
  kubectl create serviceaccount --namespace kube-system tiller
  kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller

  helm init --service-account tiller --kubeconfig ${KUBECONFIG} --wait
}


function install-spark-operator {
  echo "installing spark operator == 0.3.1"
  kubectl apply -f "${CURRENT_DIR}/hack/spark-operator-crds/"
  kubectl create serviceaccount --namespace default spark
  kubectl create clusterrolebinding spark-cluster-rule --clusterrole=cluster-admin --serviceaccount=default:spark
  helm repo add incubator http://storage.googleapis.com/kubernetes-charts-incubator
  helm install incubator/sparkoperator --namespace spark-operator --set enableBatchScheduler=true --version 0.3.1 --set operatorImageName=tommylike/spark-operator --set operatorVersion=0.0.5 --set enableWebhook=true
}

function install-volcano {
    echo "installing volcano 0.2.0"
    kubectl apply -f "${CURRENT_DIR}/hack/volcano-0.2.yaml"
}
echo "Preparing environment for spark operator on volcano demos"

check-prerequisites

kind-cluster-up

export KUBECONFIG="$(kind get kubeconfig-path --name='integration')"

install-helm

install-spark-operator

install-volcano
echo "all required services has been running up....
[k8s config]: export KUBECONFIG=\"$(kind get kubeconfig-path --name=integration)\""

