#!/usr/bin/env bash

# default. override in .env
PORTS="2001"

source .env


IFS=","
DPORTS=""
for i in $PORTS; do
  if [[ $i != "" ]]; then
    if [[ $DPORTS == "" ]]; then
      DPORTS="-p $i:$i"
    else
      DPORTS="$DPORTS -p $i:$i"
    fi
  fi
done

echo $DPORTS
