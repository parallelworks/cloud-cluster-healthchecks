#!/bin/bash

# Until we can read a config, set vars here
HEALTH_LOG_FILE=/tmp/healthcheck.log
HEALTH_CHECKS=(check_services check_ssh check_lustre)

# Get the node's type. Certain checks only run on certain nodes.
export HOSTNAME="$(hostname)"
NODE_TYPE=""
if [[ $HOSTNAME == *mgmt* ]]; then
  NODE_TYPE="controller"
else
  NODE_TYPE="compute"
fi

# Main function
main () {
log starting cluster health checks...
for i in "${HEALTH_CHECKS[@]}"; do
  ${i}
done
  log all checks completed!
}

# Simple logging function
log () {
  echo "[`date`] $@" 2>&1 >> $HEALTH_LOG_FILE
}

# Get return code for a check. requires a TYPE and CHECK.
check_rc () {
  RC=$(echo $?)
  TYPE=${1}
  CHECK=${2}
  if [ $# -ne 2 ]; then
    log check_rc requires exactly 2 arguments!
    log make sure you have a TYPE and CHECK
    exit 2
  fi

  if [ $RC = 0 ]; then
    log $TYPE check for $CHECK successful. continue
  else
    log $TYPE check for $CHECK unsuccessful. exit
    exit 1
  fi
}

# health check functions begin here

# Check services that should be running
check_services () {
  # Get services to check by node type
  if [ "$NODE_TYPE" == "controller" ]; then
    SERVICES=(slurmctld munge)
  elif [ "$NODE_TYPE" == "compute" ]; then
    SERVICES=(slurmd munge)
  fi

  # Check health of services
  for i in "${SERVICES[@]}"; do
    systemctl is-active -q ${i}
    check_rc service ${i}
  done
  log all services healthy!
}

check_ssh () {
  # Get hosts to check ssh access
  if [ "$NODE_TYPE" == "controller" ]; then
    SSH_HOSTS=(usercontainer)  
  fi

  for i in "${SSH_HOSTS[@]}"; do
    ssh -q ${i} hostname > /dev/null
    check_rc ssh ${i}
  done
  log ssh checks healthy!
}

check_lustre () {
  # check if lustre is configured (improve this!)
  if grep -q '"fsname": "lustre"' /tmp/startnode.yaml; then
    IS_LUSTRE=true 
  else
    log lustre is not configured. continue
  fi

  if [ "$IS_LUSTRE" == "true" ]; then
    # make sure lustre is mounted and writable
    mountpoint /lustre > /dev/null 2>&1
    check_rc mount lustre
    echo 1 > /lustre/healthcheck
    check_rc write lustre
    rm /lustre/healthcheck

    # todo: check status of lustre servers, usable disk (for prolog)
  fi
}

main
