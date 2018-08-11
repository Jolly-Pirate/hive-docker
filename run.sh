#!/usr/bin/env bash
#
# Steem node manager
# Released under GNU AGPL by Someguy123
# Modified by Jolly-Pirate
#

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOCKER_DIR="$DIR/dkr"
FULL_DOCKER_DIR="$DIR/dkr_fullnode"
DATADIR="$DIR/data"
DOCKER_NAME="seed"
STEEMD_VERSION="$2"
REPLAY_FAST="$2"

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
fi

if [[ ! -f data/witness_node_data_dir/config.ini ]]; then
  echo "config.ini not found. copying example (seed)";
  cp data/witness_node_data_dir/config.ini.example.stable data/witness_node_data_dir/config.ini
fi

if [[ $1 == *"build"* && $2 == "" ]]; then
  echo $RED"Specify the steemd version to build, e.g. stable"$RESET
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
  echo "    build - build steem container from docker file (pass the steemd version as argument)"
  echo "    dlblocks - download and decompress the blockchain to speed up your first start"
  echo "    enter - enter a bash session in the container"
  echo "    install - pull latest docker image from server (no compiling)"
  echo "    install_docker - install docker"
  echo "    install_full - pulls latest (FULL NODE FOR RPC) docker image from server (no compiling)"
  echo "    install_ntp - install and configure NTP synchronization"
  echo "    logs - show all logs inc. docker logs, and steem logs"
  echo "    preinstall - install linux utils packages"
  echo "    rebuild - build steem container (from docker file), and then restarts it"
  echo "    remote_wallet - open cli_wallet in the container connecting to a remote seed"
  echo "    replay - start steem container (in replay mode)"
  echo "    replay fullfast - replay steem full node in fast mode (skip feeds older than 7 days)"
  echo "    restart - restart steem container"
  echo "    shm_size - resize /dev/shm to a given size, e.g. ./run.sh shm_size 10G"
  echo "    start - start steem container"
  echo "    status - show status of steem container"
  echo "    stop - stop steem container"
  echo "    version - get steemd version from the running container (e.g. seed or witness)"
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
}

version() {
  if docker ps | grep -q seed; then
    echo "steemd -v" | docker exec -i witness bash
    elif docker ps | grep -q witness; then
    echo "steemd -v" | docker exec -i witness bash
  else
    echo "No seed/witness container running"
  fi
}

preinstall() {
  sudo apt update
  sudo apt install -y curl git wget xz-utils
}

install_ntp() {
  sudo apt install -y ntp
  echo "minpoll 5" | sudo tee -a /etc/ntp.conf > /dev/null
  echo "maxpoll 7" | sudo tee -a /etc/ntp.conf > /dev/null
  sudo systemctl enable ntp
  sudo systemctl restart ntp
  echo
  echo $BOLD'NTP status'$RESET$GREEN
  timedatectl | grep 'NTP synchronized'
  ntptime | grep '  offset' | awk '{print $1,$2,$3}' | tr -d ','
  echo $RESET
}

build() {
  echo $GREEN"Building docker container for steemd version: $STEEMD_VERSION"$RESET
  cd $DOCKER_DIR
  docker build --no-cache --build-arg steemd_version=$STEEMD_VERSION -t steem .
  # clean image remnants
  echo $GREEN"Removing remnant docker images"$RESET
  docker images | if grep -q '<none>' ; then docker images | grep '<none>' | awk '{print $3}' | xargs docker rmi -f ; fi
}

build_full() {
  echo $GREEN"Building full-node docker container for steemd version: $STEEMD_VERSION"$RESET
  cd $FULL_DOCKER_DIR
  docker build --no-cache --build-arg steemd_version=$STEEMD_VERSION -t steem .
  # clean image remnants
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
  curl https://get.docker.com | sh
  if [ "$EUID" -ne 0 ]; then
    echo "Adding user $(whoami) to docker group"
    sudo usermod -aG docker $(whoami)
    echo "IMPORTANT: Please re-login (or close and re-connect SSH) for docker to function correctly"
  fi
}

install() {
  echo "Loading image from someguy123/steem"
  docker pull someguy123/steem
  echo "Tagging as steem"
  docker tag someguy123/steem steem
  echo "Installation completed. You may now configure or run the server"
}

install_full() {
  echo "Loading image from someguy123/steem"
  docker pull someguy123/steem:latest-full
  echo "Tagging as steem"
  docker tag someguy123/steem:latest-full steem
  echo "Installation completed. You may now configure or run the server"
}

seed_exists() {
  seedcount=$(docker ps -a -f name="^/"$DOCKER_NAME"$" | wc -l)
  if [[ $seedcount -eq 2 ]]; then
    return 0
  else
    return -1
  fi
}

seed_running() {
  seedcount=$(docker ps -f 'status=running' -f name=$DOCKER_NAME | wc -l)
  if [[ $seedcount -eq 2 ]]; then
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
  seed_exists
  if [[ $? == 0 ]]; then
    docker start $DOCKER_NAME
  else
    docker run $DPORTS -v /dev/shm:/shm -v "$DATADIR":/steem -d --name $DOCKER_NAME -t steem steemd --data-dir=/steem/witness_node_data_dir
  fi
}

replay() {
  echo "Removing old container"
  docker rm $DOCKER_NAME
  if [[ $REPLAY_FAST == "fullfast" ]]; then
    LASTWEEKUTCDATE=$(date -d "-7 days" +%s)
    echo "Replaying full node in fast mode (skipping feeds older than 7 days)"
    docker run $DPORTS -v /dev/shm:/shm -v "$DATADIR":/steem -d --name $DOCKER_NAME -t steem steemd --data-dir=/steem/witness_node_data_dir --replay --follow-start-feeds=$LASTWEEKUTCDATE
    echo "Started."
  else
    echo "Running steem with replay..."
    docker run $DPORTS -v /dev/shm:/shm -v "$DATADIR":/steem -d --name $DOCKER_NAME -t steem steemd --data-dir=/steem/witness_node_data_dir --replay
    echo "Started."
  fi
}

shm_size() {
  echo "Setting SHM to $1"
  sudo mount -o remount,size=$1 /dev/shm
}

stop() {
  echo $RED"Stopping container..."$RESET
  docker stop $DOCKER_NAME
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
  docker logs --tail=30 $DOCKER_NAME
  #echo $RED"INFO AND DEBUG LOGS: "$RESET
  #tail -n 30 $DATADIR/{info.log,debug.log}
}

status() {
  seed_exists
  if [[ $? == 0 ]]; then
    echo "Container exists?: "$GREEN"YES"$RESET
  else
    echo "Container exists?: "$RED"NO (!)"$RESET
    echo "Container doesn't exist, thus it is NOT running. Run $0 build && $0 start"$RESET
    return
  fi
  
  seed_running
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
  build_full)
    echo "You may want to use '$0 install_full' for a binary image instead, it's faster."
    build_full
  ;;
  install_docker)
    install_docker
  ;;
  install)
    install
  ;;
  install_full)
    install_full
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
  restart)
    stop
    sleep 5
    start
  ;;
  rebuild)
    stop
    sleep 5
    build
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
