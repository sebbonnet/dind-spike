#!/usr/bin/env bash
set -e
scriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
projectDir="${scriptDir}/../"

source ${scriptDir}/log.sh

function setup_node() {
    local start_index=$1
    local node_count=$2
    local zone=$3

    for ((node_index=$((start_index)); node_index<$((node_count + start_index)); node_index++));
    do
        node="kube-node-${node_index}"
        pv_path="/mnt/pv-zone-${zone}"
        kubectl --context dind label --overwrite node ${node} failure-domain.beta.kubernetes.io/zone=eu-west-1${zone}
        docker exec kube-node-${node_index} mkdir -p ${pv_path}

        if [[ "${DIND_VERSION}" = "1.8" ]] || [[ "${DIND_VERSION}" = "1.9" ]]; then
            cat <<EOF | kubectl --context dind apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv-${zone}-${node_index}
  annotations:
    "volume.alpha.kubernetes.io/node-affinity": '{
            "requiredDuringSchedulingIgnoredDuringExecution": {
                "nodeSelectorTerms": [
                    { "matchExpressions": [
                        { "key": "failure-domain.beta.kubernetes.io/zone",
                          "operator": "In",
                          "values": ["eu-west-1${zone}"]
                        }
                    ]}
                 ]}
              }'
spec:
  capacity:
    storage: 100Mi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: "standard-zone-${zone}"
  local:
    path: ${pv_path}
EOF
        else
            cat <<EOF | kubectl --context dind apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv-${zone}-${node_index}
spec:
  capacity:
    storage: 100Mi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: standard-zone-${zone}
  local:
    path: ${pv_path}
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: failure-domain.beta.kubernetes.io/zone
          operator: In
          values:
          - eu-west-1${zone}
EOF
        fi
    done
}

function create_storage_class() {
    local zone=$1
    cat <<EOF | kubectl --context dind apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard-zone-${zone}
provisioner: kubernetes.io/no-provisioner
EOF
}

function create_test_namespace() {
        cat <<EOF | kubectl --context dind apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: test-cassandra-operator
EOF
}

function create_cassandra_crd() {
    kubectl --context dind apply -f ${projectDir}/kubernetes-resources/cassandra-operator-crd.yml
}

log "Downloading the dind cluster"
DIND_VERSION=${DIND_VERSION:-"1.10"}
curl "https://cdn.rawgit.com/kubernetes-sigs/kubeadm-dind-cluster/master/fixed/dind-cluster-v${DIND_VERSION}.sh" -o "dind-cluster-v${DIND_VERSION}.sh"
chmod +x dind-cluster-v${DIND_VERSION}.sh
#./dind-cluster-v${DIND_VERSION}.sh clean

FEATURE_GATES="${FEATURE_GATES:-MountPropagation=true,PersistentLocalVolumes=true}"
KUBELET_FEATURE_GATES="${KUBELET_FEATURE_GATES:-MountPropagation=true,DynamicKubeletConfig=true,PersistentLocalVolumes=true}"

# bootstrap the cluster
zone_a_node_count=2
zone_b_node_count=2
zone_c_node_count=0
numNodes=$((zone_a_node_count + zone_b_node_count + zone_c_node_count))
log "Creating the dind cluster"
FEATURE_GATES=${FEATURE_GATES} KUBELET_FEATURE_GATES=${KUBELET_FEATURE_GATES} NUM_NODES=${numNodes} ./dind-cluster-v${DIND_VERSION}.sh up

# add kubectl directory to PATH
export PATH="$HOME/.kubeadm-dind-cluster:$PATH"

log "Preparing the cluster for operator deployment"
setup_node 1 ${zone_a_node_count} a
setup_node $((1 + ${zone_a_node_count})) ${zone_b_node_count} b
setup_node $((1 + ${zone_a_node_count} + ${zone_b_node_count})) ${zone_c_node_count} c

create_storage_class a
create_storage_class b
create_storage_class c

create_test_namespace

create_cassandra_crd