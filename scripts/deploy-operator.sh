#!/usr/bin/env bash
set -e

scriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
projectDir="${scriptDir}/../"

source ${scriptDir}/pipeline.sh
source ${scriptDir}/log.sh

log "Deploying the operator"
deployOperator skycirrus/cassandra-operator:v0.49.0 dind test-cassandra-operator test-cassandra-operator.cassandra-operator.dev.dind

log "Creating the cluster"
cat <<EOF | kubectl --context dind -n test-cassandra-operator apply -f -
apiVersion: core.sky.uk/v1alpha1
kind: Cassandra
metadata:
  name: mycluster
spec:
  pod:
    image: "skycirrus/cassandra-docker:v0998e8909a056b835c97fb354373ab3b9135db28-SNAPSHOT"
    cpu: 1m
    memory: 987Mi
    storageSize: 100Mi
  racks:
  - name: a
    replicas: 1
    storageClass: standard-zone-a
    zone: eu-west-1a
  - name: b
    replicas: 1
    storageClass: standard-zone-b
    zone: eu-west-1b
EOF

kubectl --context dind -n test-cassandra-operator get pods -o wide

for pod in mycluster-a-0 mycluster-b-0
do
    waitForPod dind test-cassandra-operator ${pod}
done

log "Watching the cluster for a bit"
count=0
maxRetry=12
until (( "$count" >= "$maxRetry" ))
do
    kubectl --context dind -n test-cassandra-operator get pods -o wide
    sleep 5
    count=$((count ++))
done

log "Done"
