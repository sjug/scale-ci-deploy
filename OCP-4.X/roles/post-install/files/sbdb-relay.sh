#!/bin/bash
#
# Script to deploy and verify deployment of the ovnkube-sbdb-relay
# ./sbdb-relay.sh deploy|verify
#

OVN_NS=openshift-ovn-kubernetes

init_verify() {
  SBDB_IPS=($(oc get po -o wide -n ${OVN_NS} | awk '/sbdb-relay/{ print $6 }'))
  SBDB_IPS_STR="${SBDB_IPS[@]}"
  OVNKUBE_PODS=($(oc get po -n ${OVN_NS} | awk '/ovnkube-node/{ print $1 }'))
  NODE_COUNT=${#OVNKUBE_PODS[@]}
  declare -A ready
  
  echo "SBDB relay pod IPs: ${SBDB_IPS_STR}"

  # Populate array tracking node readiness state
  for PODS in "${OVNKUBE_PODS[@]}"; do
    ready[${PODS}]=false
  done
  
  # Check SBDB connection of each ovn-controller
  READY_NODES=0
}

if [[ "$1" == "deploy" ]]; then
  FOUND=0

  echo "Deploying SBDB"
  while [ ${FOUND} -lt 1 ]; do
  OVNMASTER_PODS=($(oc get po -o wide -n ${OVN_NS} | awk '/ovnkube-master/{ print $1 }'))
    echo "Found pods: ${OVNMASTER_PODS[*]}"
    for POD in "${OVNMASTER_PODS[@]}"; do
        oc logs ${POD} -c ovnkube-master | grep relay.go
        if [[ $? -eq 0 ]]; then
          echo "Found ovnkube-master leader: ${POD}"
          YAML=$(oc logs ${POD} -c ovnkube-master | awk '/\-\-\-/,/^\w[0-9]{4}/' | head -n -1)
          echo "${YAML}" | oc create -f -
	  FOUND=1
          break
        else
          echo "${POD} does not contain relay yaml."
        fi
    done
    if [ ${FOUND} -eq 0 ]; then
      echo "Unable to find relay yaml this loop, retying in 30s."
      sleep 30
    fi
  done
elif [[ "$1" == "verify" ]]; then
  init_verify

  while [ "${READY_NODES}" -lt "${NODE_COUNT}" ] ; do
    printf "\nStarting SBDB IP search.\n"
    for POD in "${OVNKUBE_PODS[@]}"; do
      if ! ${ready[${POD}]}; then
	echo "Checking pod presence"
	oc get pod ${POD}
        if [ $? -eq 1 ]; then
          echo "Guess what, the pod disappeared. Time to explode."
	  unset ready
          break
        fi

        echo "Searching pod ${POD} for SBDB IPs."
        oc logs ${POD} -c ovn-controller | grep -E ${SBDB_IPS_STR// /|}
        if [ $? -eq 0 ]; then
          READY_NODES=$((${READY_NODES}+1));
          echo "Found ${POD} using relays (Ready ${READY_NODES}/${NODE_COUNT})."
          ready[${POD}]=true
          break
	else
          echo "${POD} isn't using the SBDB relay(s)."
        fi
      fi
    done
    if [[ -z ${ready} ]]; then
	echo "Restarting verification process"
	init_verify
    fi
  done

  echo "All ${READY_NODES} ovnkube-nodes connected to SBDB relays."
else
  echo "$(basename "$0") requires one of two parameters: deploy or verify"
fi
