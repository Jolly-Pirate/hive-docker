#!/usr/bin/env bash
#
# Steem node manager
# Released under GNU AGPL by Jolly-Pirate
# Modified from Someguy123
#

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOCKER_DIR="$DIR/dkr"
DATADIR="$DIR/data"
STEEM_VERSION="$2"
BUILD_SWITCHES_LOWMEM="-DLOW_MEMORY_NODE=ON -DCLEAR_VOTES=ON -DSKIP_BY_TX_ID=ON -DENABLE_MIRA=OFF -DSTEEM_STATIC_BUILD=ON"
BUILD_SWITCHES_RPC="-DLOW_MEMORY_NODE=OFF -DCLEAR_VOTES=OFF -DSKIP_BY_TX_ID=ON -DENABLE_MIRA=ON -DSTEEM_STATIC_BUILD=ON"
BUILD_SWITCHES_RPCAH="-DLOW_MEMORY_NODE=OFF -DCLEAR_VOTES=OFF -DSKIP_BY_TX_ID=OFF -DENABLE_MIRA=ON -DSTEEM_STATIC_BUILD=ON"
BUILD_TAG="steem:$STEEM_VERSION"
BUILD_TAG_RPC="steem:$STEEM_VERSION-rpc"
BUILD_TAG_RPCAH="steem:$STEEM_VERSION-rpcah"

# get the version only
# https://stackoverflow.com/a/42681464/5369345
function versionToInt() {
  local IFS=.
  parts=($1)
  let val=1000000*parts[0]+1000*parts[1]+parts[2]
  echo $val
}
VER="$( echo ${STEEM_VERSION#"v"} )"
# only numbers in version
if [[ $VER =~ ^[0-9.]+$ ]]; then
  versionIsNum=1
  versionToInt $VER
fi
if [[ $val -lt 20011 && versionIsNum -eq 1 ]]; then
  BUILD_OS="ubuntu:xenial"
else # handles master, stable too
  BUILD_OS="ubuntu:bionic"
fi

BOLD="$(tput bold)"
RED="$(tput setaf 1)"
GREEN="$(tput setaf 2)"
YELLOW="$(tput setaf 3)"
BLUE="$(tput setaf 4)"
MAGENTA="$(tput setaf 5)"
CYAN="$(tput setaf 6)"
WHITE="$(tput setaf 7)"
RESET="$(tput sgr0)"

# default. override in .env
PORTS="2001"

if [[ -f .env ]]; then
  source .env
else
  echo $RED"Missing .env file, please create one before proceeding."$RESET
  exit
fi

if [[ $CONTAINER_TYPE != +(seed|witness|rpc|rpcah) ]]; then
  echo $RED"CONTAINER_TYPE not defined in the .env file. Set it to seed, witness, rpc or rpcah."$RESET
  exit
fi

if [[ ! $DOCKER_NAME ]]; then
  echo $RED"DOCKER_NAME not defined in the .env file"$RESET
  exit
fi

if [[ ! $SHM_DIR ]]; then
  echo $RED"SHM_DIR not defined in the .env file"$RESET
  exit
fi

if [[ ! -f $DATADIR/witness_node_data_dir/config.ini ]]; then
  echo $RED"Configuration file not found. Copying example config.ini from template (seed)"$RESET
  cp $DATADIR/witness_node_data_dir/config-example.ini $DATADIR/witness_node_data_dir/config.ini
fi

if [[ $CONTAINER_TYPE == "witness" ]] && grep -q -e '^p2p-endpoint.*=.*' $DATADIR/witness_node_data_dir/config.ini; then
  echo $RED"Detected witness node, disabling p2p-endpoint in config.ini."$RESET
  sed -i $DATADIR/witness_node_data_dir/config.ini -r -e 's/^p2p-endpoint/# p2p-endpoint/g'
fi

if [[ $1 == *"build"* && $2 == "" ]]; then
  echo $RED"Specify the steemd version to build, for example: ./run.sh build master"$RESET
  exit
fi

IFS=","
DPORTS=""
for i in $PORTS; do
  if [[ $i != "" ]]; then
    if [[ $DPORTS == "" ]]; then
      DPORTS="-p0.0.0.0:$i:$i"
    else
      DPORTS="$DPORTS -p0.0.0.0:$i:$i"
    fi
  fi
done

help() {
  echo "Usage: $0 COMMAND [DATA]"
  echo
  echo "Commands: "
  echo "    build - build steem container (seed, witness, rpc or rpcah) from docker file (pass steem version as argument)"
  echo "    dlblocks - download and decompress the blockchain to speed up your first start"
  echo "    enter - enter a bash session in the container"
  echo "    install - pull latest docker image from server (no compiling)"
  echo "    install_docker - install docker"
  echo "    install_ntp - install and configure NTP synchronization"
  echo "    logs - live logs of the running container"
  echo "    preinstall - install linux utils packages"
  echo "    remote_wallet - open cli_wallet in the container connecting to a remote seed"
  echo "    replay - start steem container in replay mode"
  echo "    restart - restart steem container"
  echo "    shm_size - set /dev/shm to a given size, for example: ./run.sh shm_size 60G"
  echo "    start - start steem container"
  echo "    status - show status of steem container"
  echo "    stop - stop steem container (wait up to 300s for it to shutdown cleanly)"
  echo "    kill - force stop steem container"
  echo "    version - get steemd version from the running container"
  echo "    wallet - open cli_wallet in the container"
  echo
  exit
}

optimize() {
  #echo    75 | sudo tee /proc/sys/vm/dirty_background_ratio
  #echo  1000 | sudo tee /proc/sys/vm/dirty_expire_centisecs
  #echo    80 | sudo tee /proc/sys/vm/dirty_ratio
  #echo 30000 | sudo tee /proc/sys/vm/dirty_writeback_centisecs
  echo $GREEN'Clearing caches. Current setting:' $(cat /proc/sys/vm/drop_caches)$RESET
  echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
  
  echo $GREEN'Configuring swappiness. Current setting:' $(cat /proc/sys/vm/swappiness)$RESET
  #swappiness
  sudo sysctl vm.swappiness=1
  #set swappiness on boot
  if ! grep -q -e '^vm.swappiness' /etc/sysctl.conf; then
    sudo cp -rpn /etc/sysctl.conf /etc/sysctl.bak
    echo 'vm.swappiness = 1' | sudo tee -a /etc/sysctl.conf > /dev/null # -a append
    grep -e '^vm.swappiness' /etc/sysctl.conf
  else
    sudo sed -i /etc/sysctl.conf -r -e 's/^vm.swappiness.*=.*/vm.swappiness = 1/g'
    grep -e '^vm.swappiness' /etc/sysctl.conf
  fi
}

version() {
  if docker ps | grep -wq $DOCKER_NAME; then
    echo "steemd -v" | docker exec -i $DOCKER_NAME bash
  else
    echo "Container not running"
  fi
}

netstat() {
  if docker ps | grep -wq $DOCKER_NAME; then
    echo "netstat -pevan | grep steemd" | docker exec -i $DOCKER_NAME bash
  else
    echo "Container not running"
  fi
}

preinstall() {
  sudo apt update
  sudo apt install -y curl git wget xz-utils
}

install_ntp() {
  sudo apt install -y ntp
  if ! grep -q "minpoll 5" /etc/ntp.conf; then echo "minpoll 5" | sudo tee -a /etc/ntp.conf > /dev/null; fi
  if ! grep -q "maxpoll 7" /etc/ntp.conf; then echo "maxpoll 7" | sudo tee -a /etc/ntp.conf > /dev/null; fi
  sudo systemctl enable ntp
  sudo systemctl restart ntp
  echo
  echo $BOLD'NTP status'$RESET$GREEN
  timedatectl | grep 'synchronized'
  ntptime | grep '  offset' | awk '{print $1,$2,$3}' | tr -d ','
  echo $RESET
}

build() {
  echo $GREEN"Building image $BUILD_TAG"$RESET
  cd $DOCKER_DIR
  if [[ $CONTAINER_TYPE == "seed" || $CONTAINER_TYPE == "witness" ]]; then
    docker build --no-cache --build-arg BUILD_OS=$BUILD_OS --build-arg STEEM_VERSION=$STEEM_VERSION --build-arg BUILD_SWITCHES=$BUILD_SWITCHES_LOWMEM --tag $BUILD_TAG .
    docker tag $BUILD_TAG steem:latest
  fi
  if [[ $CONTAINER_TYPE == "rpc" ]]; then
    docker build --no-cache --build-arg BUILD_OS=$BUILD_OS --build-arg STEEM_VERSION=$STEEM_VERSION --build-arg BUILD_SWITCHES=$BUILD_SWITCHES_RPC --tag $BUILD_TAG_RPC .
    docker tag $BUILD_TAG_RPC steem:latest
  fi
  if [[ $CONTAINER_TYPE == "rpcah" ]]; then
    docker build --no-cache --build-arg BUILD_OS=$BUILD_OS --build-arg STEEM_VERSION=$STEEM_VERSION --build-arg BUILD_SWITCHES=$BUILD_SWITCHES_RPCAH --tag $BUILD_TAG_RPCAH .
    docker tag $BUILD_TAG_RPCAH steem:latest
  fi
  echo $GREEN"Retagged the build as steem:latest"$RESET
  echo $GREEN"Removing remnant docker images"$RESET
  docker images | if grep -q '<none>' ; then docker images | grep '<none>' | awk '{print $3}' | xargs docker rmi -f ; fi
}

dlblocks() {
  mkdir -p "$DATADIR/blockchain"
  echo "Removing old block log"
  sudo rm -f $DATADIR/witness_node_data_dir/blockchain/block_log
  sudo rm -f $DATADIR/witness_node_data_dir/blockchain/block_log.index
  echo "Download @gtg's block logs..."
  wget https://gtg.steem.house/get/blockchain.xz/block_log.xz -O $DATADIR/witness_node_data_dir/blockchain/block_log.xz
  echo "Decompressing block log... this may take a while..."
  xz -d $DATADIR/witness_node_data_dir/blockchain/block_log.xz -v
  echo "FINISHED. Blockchain downloaded and decompressed"
  echo "Remember to resize your /dev/shm, and run with replay!"
  echo "$ ./run.sh shm_size SIZE (e.g. 8G)"
  echo "$ ./run.sh replay"
}

install_docker() {
  #get latest version
  curl https://get.docker.com | sh
  if [ "$EUID" -ne 0 ]; then
    echo "Adding user $(whoami) to docker group"
    sudo usermod -aG docker $(whoami)
    echo "IMPORTANT: Please re-login (or close and re-connect SSH) for docker to function correctly"
  fi
}

install() {
  if [[ $STEEM_VERSION == "" ]]; then
    echo $RED"Specify the steemd version to install, for example: ./run.sh install v0.20.12"$RESET
    exit
  fi
  echo "Loading image from jollypirate/steem:$STEEM_VERSION"
  docker pull jollypirate/steem:$STEEM_VERSION
  if docker tag jollypirate/steem:$STEEM_VERSION steem; then
    echo "Tagged as steem."
    echo "Installation completed. You may now configure or run the server."
  fi
}

container_exists() {
  containercount=$(docker ps -a -f name="^/"$DOCKER_NAME"$" | wc -l)
  if [[ $containercount -eq 2 ]]; then
    return 0
  else
    return -1
  fi
}

container_running() {
  containercount=$(docker ps -f 'status=running' -f name=$DOCKER_NAME | wc -l)
  if [[ $containercount -eq 2 ]]; then
    return 0
  else
    return -1
  fi
}

# Important for AppBase:
# The default data directory is now '/root/.steemd' instead of '/steem/witness_node_data_dir'.
# Please move your data directory to '/root/.steemd' or specify '--data-dir=/steem/witness_node_data_dir' to continue using the current data directory.

start() {
  echo $GREEN"Starting container..."$RESET
  container_exists
  if [[ $? == 0 ]]; then
    docker start $DOCKER_NAME
  else
    docker run $DPORTS -v $SHM_DIR:/shm -v "$DATADIR":/steem -d --log-opt max-size=1g --log-opt max-file=1 -h $DOCKER_NAME --name $DOCKER_NAME -t steem steemd --data-dir=/steem/witness_node_data_dir --tags-skip-startup-update
  fi
  
  sleep 1
  if [[ $(docker inspect -f {{.State.Running}} $DOCKER_NAME) == true ]]; then
    echo $GREEN"Container $DOCKER_NAME successfully started"$RESET
  else
    echo $RED"Container $DOCKER_NAME didn't start!"$RESET
  fi
}

replay() {
  stop
  
  if [[ $CONTAINER_TYPE == "rpc" || $CONTAINER_TYPE == "rpcah" ]]; then
    echo "Replaying optimized RPC node (skipping feeds older than 7 days)"
    LAST_WEEK_UTC_DATE=$(date -d "-7 days" +%s)
    #NOTE --tags-start-promoted only if the tag plugin is loaded. e.g. remove it for a AH node
    RPC_FEEDS="--follow-start-feeds=$LAST_WEEK_UTC_DATE"
    if grep -q data/witness_node_data_dir/config.ini -e '^plugin.*tags.*' ; then
      RPC_TAGS="--tags-start-promoted=$LAST_WEEK_UTC_DATE"
    else
      RPC_TAGS=""
    fi
    echo $RPC_FEEDS $RPC_TAGS
    #docker run $DPORTS -v $SHM_DIR:/shm -v "$DATADIR":/steem -d --log-opt max-size=1g --name $DOCKER_NAME -t steem steemd --data-dir=/steem/witness_node_data_dir --replay $RPC_FEEDS $RPC_TAGS
    docker run $DPORTS -v $SHM_DIR:/shm -v "$DATADIR":/steem -d --log-opt max-size=1g --name $DOCKER_NAME -t steem steemd --data-dir=/steem/witness_node_data_dir --replay --set-benchmark-interval 100000 $RPC_FEEDS
  else
    echo "Replaying $CONTAINER_TYPE node..."
    docker run $DPORTS -v $SHM_DIR:/shm -v "$DATADIR":/steem -d --log-opt max-size=1g --name $DOCKER_NAME -t steem steemd --data-dir=/steem/witness_node_data_dir --replay --set-benchmark-interval 100000
  fi
  
  sleep 1
  if [[ $(docker inspect -f {{.State.Running}} $DOCKER_NAME) == true ]]; then
    echo $GREEN"Container $DOCKER_NAME successfully started"$RESET
  else
    echo $RED"Container $DOCKER_NAME didn't start!"$RESET
  fi
}

shm_size() {
  echo "Setting SHM to $1"
  sudo mount -o remount,size=$1 /dev/shm
}

stop() {
  echo $RED"Stopping and removing container $DOCKER_NAME..."$RESET
  time docker stop -t 300 $DOCKER_NAME
  # no need to loop since we're waiting on the stop
  #  while [[ $(docker inspect -f {{.State.Running}} $DOCKER_NAME) == true ]]
  #  do
  #    echo $CYAN"Waiting for container to stop cleanly"$RESET
  #    sleep 2
  #  done
  docker logs $DOCKER_NAME --tail=8
  docker rm $DOCKER_NAME
}

kill() {
  echo $RED"Forcing stop and removing container $DOCKER_NAME..."$RESET
  time docker stop $DOCKER_NAME
  docker rm $DOCKER_NAME
}
enter() {
  docker exec -it $DOCKER_NAME bash
}

wallet() {
  docker exec -it $DOCKER_NAME cli_wallet
}

remote_wallet() {
  docker run -v "$DATADIR":/steem --rm -it steem cli_wallet -s wss://steemd.privex.io
}

logs() {
  echo $BLUE"DOCKER LOGS: "$RESET
  docker logs --tail=50 --follow $DOCKER_NAME
  #echo $RED"INFO AND DEBUG LOGS: "$RESET
  #tail -n 30 $DATADIR/{info.log,debug.log}
}

status() {
  container_exists
  if [[ $? == 0 ]]; then
    echo "Container exists?: "$GREEN"YES"$RESET
  else
    echo "Container exists?: "$RED"NO (!)"$RESET
    echo "Container doesn't exist, thus it is NOT running. Run $0 build && $0 start"$RESET
    return
  fi
  
  container_running
  if [[ $? == 0 ]]; then
    echo "Container running?: "$GREEN"YES"$RESET
  else
    echo "Container running?: "$RED"NO (!)"$RESET
    echo "Container isn't running. Start it with $0 start"$RESET
    return
  fi
}

if [ "$#" -lt 1 ]; then
  help
fi

case $1 in
  build)
    echo "You may want to use '$0 install' for a binary image instead, it's faster."
    build
  ;;
  install_docker)
    install_docker
  ;;
  install)
    install
  ;;
  start)
    start
  ;;
  replay)
    replay
  ;;
  shm_size)
    shm_size $2
  ;;
  stop)
    stop
  ;;
  kill)
    kill
  ;;
  restart)
    stop
    start
  ;;
  optimize)
    echo "Applying recommended dirty write settings..."
    optimize
  ;;
  status)
    status
  ;;
  wallet)
    wallet
  ;;
  remote_wallet)
    remote_wallet
  ;;
  dlblocks)
    dlblocks
  ;;
  enter)
    enter
  ;;
  logs)
    logs
  ;;
  version)
    version
  ;;
  netstat)
    netstat
  ;;
  preinstall)
    preinstall
  ;;
  install_ntp)
    install_ntp
  ;;
  *)
    echo "Invalid cmd"
    help
  ;;
esac
