#!/bin/bash -e

scriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
projectDir="${scriptDir}/../"
resourcesDir="${projectDir}/kubernetes-resources"
testImagePath="skycirrus/cassandra-operator"

source ${scriptDir}/waitFor.sh

function isOnMaster() {
    currentRevision=$(git rev-parse HEAD)
    branch=$(git branch -r --contains ${currentRevision})
    set +e
    echo "$branch" | grep -q "origin/master"
    result=$?
    set -e
    return ${result}
}

function getCurrentVersionTrimmed() {
  # Parses the version from output "\nProject version: 0.211.0\n".
  ../gradlew -q currentVersion | tail -n1 | awk '{print $3;}'
}

function deployOperator() {
    local operatorImage=$1
    local context=$2
    local namespace=$3
    local ingressHost=$4
    local deployment=cassandra-operator
    local operatorArgs='["--allow-empty-dir=true", "--log-level=debug"]'
    local tmpDir=$(mktemp -d)
    trap '{ CODE=$?; rm -rf ${tmpDir} ; exit ${CODE}; }' EXIT

    k8Resources="cassandra-operator-rbac.yml cassandra-node-rbac.yml cassandra-operator-deployment.yml"
    for k8Resource in ${k8Resources}
    do
        sed -e "s@\$TARGET_NAMESPACE@$namespace@g" \
            -e "s@\$OPERATOR_IMAGE@$operatorImage@g" \
            -e "s@\$OPERATOR_ARGS@$operatorArgs@g" \
            -e "s@\$INGRESS_HOST@$ingressHost@g" \
            ${resourcesDir}/${k8Resource} > ${tmpDir}/${k8Resource}
        kubectl --context ${context} -n ${namespace} apply -f ${tmpDir}/${k8Resource}
    done

    waitForDeployment ${context} ${namespace} ${deployment}
}

function buildImageAndDeploy() {
    local context=${CONTEXT:-"dind"}
    local domain=${DOMAIN:-"dev.dind"}

    buildVersion=$(getCurrentVersionTrimmed)
    localImage="local/cassandra-operator:v${buildVersion}"
    docker build . -t ${localImage}

    testImage="$testImagePath:v$buildVersion"
    docker tag ${localImage} ${testImage}
    docker push ${testImage}

    deployOperator ${testImage} ${context} test-cassandra-operator test-cassandra-operator.cassandra-operator.${domain}
}
