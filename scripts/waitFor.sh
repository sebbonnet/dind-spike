#!/bin/bash -e

function waitForDeployment {
    local count=0
    local sleepBetweenRetries=2
    local maxRetry=150 # 5mins max, as corresponds to: maxRetry * sleepBetweenRetries
    local context=$1
    local namespace=$2
    local deployment=$3

    local desiredReplicas=1
    local updatedReplicas=""
    local readyReplicas=""
    until ([[ "$desiredReplicas" = "$updatedReplicas" ]] && [[ "$desiredReplicas" = "$readyReplicas" ]]) || (( "$count" >= "$maxRetry" )); do
        count=$((count+1))
        echo "Waiting for ${namespace}.${deployment} to have ${desiredReplicas} updated replicas. Attempt: $count"
        readyReplicas=$(kubectl --context ${context} -n ${namespace} get deployment ${deployment} -o go-template="{{.status.readyReplicas}}")
        updatedReplicas=$(kubectl --context ${context} -n ${namespace} get deployment ${deployment} -o go-template="{{.status.updatedReplicas}}")

        sleep ${sleepBetweenRetries}
    done

    if [[ "$desiredReplicas" != "$updatedReplicas" ]] || [[ "$desiredReplicas" != "$readyReplicas" ]]; then
        echo "Deployment failed to become ready after ${maxRetry} retries"
        exit 1
    fi
    echo "Deployment is ready"
}

function waitForPod {
    local count=0
    local maxRetry=150 # 5mins max
    local podStatus="{{ range .status.conditions }}{{ .type }}={{ .status }} {{ end }}"
    local podStatuses="{{ range .items }}$podStatus{{ end }}"

    local context=$1
    local namespace=$2
    local matcher=$3
    local statusTemplate=${podStatus}

    if [[ ${matcher} = *"="* ]]; then
      statusTemplate=${podStatuses}
    fi

    ready=""
    until [[ ${ready} = "0" ]] || (( "$count" >= "$maxRetry" )); do
        count=$((count+1))
        echo "Waiting for pod: $matcher in namespace: $namespace. Attempt: $count"
        status=$(kubectl --context ${context} -n ${namespace} get po ${matcher} -o go-template="$statusTemplate" || true)
        set +e
        echo "$status" | grep "Ready=True"
        ready=$?
        set -e
        sleep 2
    done

    if [[ ${ready} != "0" ]]; then
        echo "Pod failed to become ready after ${maxRetry} retries"
        exit 1
    fi
    echo "Pod is ready"
}
