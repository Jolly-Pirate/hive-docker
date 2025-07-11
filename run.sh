#!/usr/bin/env bash
#
# Hive node manager
# Released under GNU AGPL by Jolly-Pirate
# Modified from Someguy123
#

BOLD="$(tput bold)"
RED="$(tput setaf 1)"
GREEN="$(tput setaf 2)"
YELLOW="$(tput setaf 3)"
BLUE="$(tput setaf 4)"
MAGENTA="$(tput setaf 5)"
CYAN="$(tput setaf 6)"
WHITE="$(tput setaf 7)"
RESET="$(tput sgr0)"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$DIR/dkr"
DATADIR="$DIR/data"
BUILD_VERSION="$2"
REMOTE_WS="wss://api.deathwing.me"

# default. override in .env
PORTS="2001"

if [[ -f .env ]]; then
  source .env
else
  echo $RED"Missing .env, copying example .env from template (seed). Edit it before running this again."$RESET
  cp .env-example .env
  exit
fi

if [[ $CONTAINER_TYPE != +(seed|witness|rpc|fakenet|testnet) ]]; then
  echo $RED"CONTAINER_TYPE not defined in the .env file. Set it to seed, witness, rpc, fakenet or testnet."$RESET
  exit
fi

if [[ $CONTAINER_TYPE == +(fakenet|testnet) && ! $CHAIN_ID ]]; then
  echo $RED"Missing CHAIN_ID in .env for the fakenet or testnet"$RESET
  exit
fi

if [[ $CONTAINER_TYPE == +(fakenet|testnet) && $CHAIN_ID ]]; then
  CHAIN_ID_PARAM="--chain-id=$CHAIN_ID"
  echo "Starting a $CONTAINER_TYPE with $CHAIN_ID_PARAM"
fi

if [[ ! $DOCKER_NAME ]]; then
  echo $RED"DOCKER_NAME not defined in the .env file"$RESET
  exit
fi

if [[ ! $SHM_DIR ]]; then
  echo $RED"SHM_DIR not defined in the .env file"$RESET
  exit
fi

if [[ ! $BUILD_OS ]]; then
  echo $RED"BUILD_OS not defined in the .env file"$RESET
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

if [[ $1 == *"build"* ]]; then
  if [[ $2 == "" ]]; then
    echo $RED"Specify the hived version to build, for example: ./run.sh build master"$RESET
    exit
  fi
fi

BUILD_SWITCHES_FAKENET="-DHIVE_CONVERTER_BUILD=ON"
BUILD_SWITCHES_TESTNET="-DBUILD_HIVE_TESTNET=ON \
-DCHAINBASE_CHECK_LOCKING=ON \
-DHIVE_LINT_LEVEL=OFF"

BUILD_TAG="hive:$BUILD_VERSION"
BUILD_TAG_FAKENET="hive:$BUILD_VERSION-fakenet"
BUILD_TAG_TESTNET="hive:$BUILD_VERSION-testnet"

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
  echo "    build <version> - build hive container (seed, witness, rpc, fakenet, testnet)"
  echo "    dlblocks - download and decompress the blockchain file"
  echo "    enter - enter a bash session in the container"
  echo "    install - pull latest docker image from server (no compiling)"
  echo "    install_docker - install docker"
  echo "    install_ntp - install and configure NTP synchronization"
  echo "    logs - live logs of the running container"
  echo "    preinstall - install linux utils packages"
  echo "    optimize - optimize the swappiness, use that option if using a swapfile"
  echo "    remote_wallet - open cli_wallet in the container connecting to a remote seed"
  echo "    replay - start hive container in replay mode"
  echo "    restart - restart hive container"
  echo "    shm_size - set /dev/shm to a given size, for example: ./run.sh shm_size 20G"
  echo "    snapshot <dump|load|pack|unpack> <snapshot_name>"
  echo "              dump|load: stop the container, dump/load snapshot and resume hived"
  echo "              pack: compress the snapshot with tar+gzip"
  echo "              unpack: decompress the snapshot"
  echo "    start - start hive container"
  echo "    save - stop hive container and save /dev/shm/shared_memory.bin"
  echo "    load - copy shared_memory.bin to /dev/shm/ and start hive container"
  echo "    compress - compress the block_log (HF26 feature)"
  echo "    status - show status of hive container"
  echo "    stop - stop hive container (wait up to 300s for it to shutdown cleanly)"
  echo "    kill - force stop hive container"
  echo "    version - get hived version from the running container"
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
  echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null

  echo $GREEN'Configuring swappiness. Current setting:' $(cat /proc/sys/vm/swappiness)$RESET
  #swappiness
  sudo sysctl vm.swappiness=10
  #set swappiness on boot
  if ! grep -q -e '^vm.swappiness' /etc/sysctl.conf; then
    sudo cp -rpn /etc/sysctl.conf /etc/sysctl.bak
    echo 'vm.swappiness = 10' | sudo tee -a /etc/sysctl.conf >/dev/null # -a append
    grep -e '^vm.swappiness' /etc/sysctl.conf
  else
    sudo sed -i /etc/sysctl.conf -r -e 's/^vm.swappiness.*=.*/vm.swappiness = 10/g'
    grep -e '^vm.swappiness' /etc/sysctl.conf
  fi
}

version() {
  if docker ps | grep -wq $DOCKER_NAME; then
    docker exec $DOCKER_NAME bash -c "echo ${BOLD}${BLUE}linux version${RESET} ; cat /etc/*release ; echo ${BOLD}${BLUE}hived version${RESET}; hived -v"
  else
    echo "Container not running"
  fi
}

netstat() {
  if docker ps | grep -wq $DOCKER_NAME; then
    echo "netstat -pevan | grep hived" | docker exec -i $DOCKER_NAME bash
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
  if ! grep -q "minpoll 5" /etc/ntp.conf; then echo "minpoll 5" | sudo tee -a /etc/ntp.conf >/dev/null; fi
  if ! grep -q "maxpoll 7" /etc/ntp.conf; then echo "maxpoll 7" | sudo tee -a /etc/ntp.conf >/dev/null; fi
  sudo systemctl enable ntp
  sudo systemctl restart ntp
  echo
  echo $BOLD'NTP status'$RESET$GREEN
  timedatectl | grep 'synchronized'
  ntptime | grep '  offset' | awk '{print $1,$2,$3}' | tr -d ','
  echo $RESET
}

build() {
  cd $DOCKER_DIR
  if [[ $REPO_SOURCE ]]; then
    echo $RED"Custom Github repo: $REPO_SOURCE"$RESET
  else
    REPO_SOURCE="https://github.com/openhive-network/hive"
    echo $RED"Default Github repo: $REPO_SOURCE"$RESET
  fi
  if [[ $CONTAINER_TYPE == +(seed|witness|rpc) ]]; then
    echo $GREEN"Building image $BUILD_TAG"$RESET
    DOCKER_BUILDKIT=1 BUILDKIT_PROGRESS=plain docker build --no-cache --build-arg BUILD_OS=$BUILD_OS --build-arg REPO_SOURCE=$REPO_SOURCE --build-arg BUILD_VERSION=$BUILD_VERSION --tag $BUILD_TAG .
    BUILT_IMAGE=$BUILD_TAG
  fi
  if [[ $CONTAINER_TYPE == "fakenet" ]]; then
    echo $GREEN"Building image $BUILD_TAG_FAKENET"$RESET
    DOCKER_BUILDKIT=1 BUILDKIT_PROGRESS=plain docker build --no-cache --build-arg BUILD_OS=$BUILD_OS --build-arg REPO_SOURCE=$REPO_SOURCE --build-arg BUILD_VERSION=$BUILD_VERSION --build-arg BUILD_SWITCHES=$BUILD_SWITCHES_FAKENET --tag $BUILD_TAG_FAKENET .
    BUILT_IMAGE=$BUILD_TAG_FAKENET
  fi
  if [[ $CONTAINER_TYPE == "testnet" ]]; then
    echo $GREEN"Building image $BUILD_TAG_TESTNET"$RESET
    DOCKER_BUILDKIT=1 BUILDKIT_PROGRESS=plain docker build --no-cache --build-arg BUILD_OS=$BUILD_OS --build-arg REPO_SOURCE=$REPO_SOURCE --build-arg BUILD_VERSION=$BUILD_VERSION --build-arg BUILD_SWITCHES=$BUILD_SWITCHES_TESTNET --tag $BUILD_TAG_TESTNET .
    BUILT_IMAGE=$BUILD_TAG_TESTNET
  fi
  echo $GREEN"Docker image built $BUILT_IMAGE"$RESET
  echo $GREEN"Removing remnant docker images"$RESET
  docker images | if grep -q '<none>'; then docker images | grep '<none>' | awk '{print $3}' | xargs docker rmi -f; fi
}

dlblocks() {
  mkdir -p "$DATADIR/witness_node_data_dir/blockchain"
  # Prompt to remove old block log
  read -e -p "Remove old block log? [Y/n] " YN
  [[ $YN == "y" || $YN == "Y" || $YN == "" ]] &&
    (
      echo "Removing old block log"
      sudo rm -f $DATADIR/witness_node_data_dir/blockchain/block_log*
    )
  read -e -p "Get compressed (c) or uncompressed (u) block_log? [C/u] " CU
  [[ $CU == "c" || $CU == "C" || $CU == "" ]] &&
    (
      echo "Downloading compressed block_log..."
      wget -c https://gtg.openhive.network/get/blockchain/compressed/block_log -O $DATADIR/witness_node_data_dir/blockchain/block_log
      wget -c https://gtg.openhive.network/get/blockchain/compressed/block_log.artifacts -O $DATADIR/witness_node_data_dir/blockchain/block_log.artifacts
    )
  [[ $CU == "u" || $CU == "U" ]] &&
    (
      echo "Downloading uncompressed block_log..."
      wget -c https://gtg.openhive.network/get/blockchain/block_log -O $DATADIR/witness_node_data_dir/blockchain/block_log
      wget -c https://gtg.openhive.network/get/blockchain/block_log.index -O $DATADIR/witness_node_data_dir/blockchain/block_log.index
    )
  echo "FINISHED. Blockchain downloaded"
  echo "Remember to resize your /dev/shm, and run with replay!"
  echo "$ ./run.sh shm_size SIZE (e.g. 20G)"
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
  if [[ $BUILD_VERSION == "" ]]; then
    echo $RED"Specify the prebuilt hived docker image to install, for example: ./run.sh install v1.27.0"$RESET
    exit
  fi
  echo "Loading image from jollypirate/hive:$BUILD_VERSION"
  docker pull jollypirate/hive:$BUILD_VERSION
  if docker tag jollypirate/hive:$BUILD_VERSION hive:$BUILD_VERSION; then
    echo "Tagged as hive:$BUILD_VERSION"
    # Prompt to update .env
    read -e -p "Add/Update TAG_VERSION to the .env file? [Y/n] " YN
    [[ $YN == "y" || $YN == "Y" || $YN == "" ]] &&
      if ! grep -q TAG_VERSION .env; then echo TAG_VERSION >>.env; fi &&
      sed -i .env -r -e "s/^TAG_VERSION.*/TAG_VERSION=$BUILD_VERSION/g"

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
# The default data directory is now '/root/.hived' instead of '/hive/witness_node_data_dir'.
# Please move your data directory to '/root/.hived' or specify '--data-dir=/hive/witness_node_data_dir' to continue using the current data directory.

start() {
  if [[ $1 == "force" ]]; then # $1 passed through the function
    FORCE_OPEN="--force-open"
    echo $GREEN"Starting container with $FORCE_OPEN"$RESET
  fi

  # Synching from scratch
  if ! compgen -G "$DATADIR/witness_node_data_dir/blockchain/block_log*" > /dev/null; then
    RESYNCHING="true"
    CHECKPOINT='checkpoint = [68500000, "04153a20e4c2adff08d2fc7566fd26d7a28fd564"]'
    cat <<EOF
${BOLD}block_log doesn't exist, will synch the blockchain from scratch with
a checkpoint, and temporarly disable the witness line in the config.ini
to speed up the synchronization${RESET}
EOF
    read -e -p $RED$BOLD"Proceed with those modifications? [Y/n] "$RESET YN
    [[ $YN == "y" || $YN == "Y" || $YN == "" ]] &&
      (
        if ! grep -q -e '^checkpoint.*04153a20e4c2adff08d2fc7566fd26d7a28fd564' $DATADIR/witness_node_data_dir/config.ini; then
          echo "$CHECKPOINT" >>$DATADIR/witness_node_data_dir/config.ini
          echo "Added to config.ini: $CHECKPOINT"
        fi

        if [[ $CONTAINER_TYPE == "witness" ]]; then
          sed -i $DATADIR/witness_node_data_dir/config.ini -r -e 's/^witness/# witness/g'
          cat <<EOF
${BLUE}${BOLD}IMPORTANT NOTE
Do a './run.sh restart' when the synchronization is complete
to re-enable the witness${RESET}"
EOF
          read -e -p "<press any key to continue>"
        fi
      )
  fi

  container_exists
  if [[ $? == 0 ]]; then
    docker start $DOCKER_NAME
  else
    # Re-enable the witness setting
    if [[ $CONTAINER_TYPE == "witness" ]] && [[ $RESYNCHING != "true" ]] && grep -q -e '# witness.*=.*' $DATADIR/witness_node_data_dir/config.ini; then
      echo "Re-enabling the witness line in the config.ini"
      sed -i $DATADIR/witness_node_data_dir/config.ini -r -e 's/^# witness/witness/g'
    fi
    docker run $DPORTS -v $SHM_DIR:/shm -v "$DATADIR":/hive -d --log-opt max-size=1g --log-opt max-file=1 -h $DOCKER_NAME --name $DOCKER_NAME -t hive:$TAG_VERSION hived --data-dir=/hive/witness_node_data_dir $FORCE_OPEN $CHAIN_ID_PARAM
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

  if [[ $1 == "force" ]]; then
    FORCE_REPLAY="--force-replay"
    echo $GREEN"Starting container with $FORCE_REPLAY"$RESET
  fi

  if [[ $CONTAINER_TYPE == "rpc" ]]; then
    echo "Replaying optimized RPC node (skipping feeds older than 7 days)"
    LAST_WEEK_UTC_DATE=$(date -d "-7 days" +%s)
    #NOTE --tags-start-promoted only if the tag plugin is loaded. e.g. remove it for a AH node
    RPC_FEEDS="--follow-start-feeds=$LAST_WEEK_UTC_DATE"
    if grep -q data/witness_node_data_dir/config.ini -e '^plugin.*tags.*'; then
      RPC_TAGS="--tags-start-promoted=$LAST_WEEK_UTC_DATE"
    else
      RPC_TAGS=""
    fi
    echo $RPC_FEEDS $RPC_TAGS
    docker run $DPORTS -v $SHM_DIR:/shm -v "$DATADIR":/hive -d --log-opt max-size=1g --name $DOCKER_NAME -t hive:$TAG_VERSION hived --data-dir=/hive/witness_node_data_dir --replay-blockchain $FORCE_REPLAY --set-benchmark-interval 100000 $RPC_FEEDS
  else
    echo "Replaying $CONTAINER_TYPE node..."
    docker run $DPORTS -v $SHM_DIR:/shm -v "$DATADIR":/hive -d --log-opt max-size=1g --name $DOCKER_NAME -t hive:$TAG_VERSION hived --data-dir=/hive/witness_node_data_dir --replay-blockchain $FORCE_REPLAY --set-benchmark-interval 100000
  fi

  sleep 1
  if [[ $(docker inspect -f {{.State.Running}} $DOCKER_NAME) == true ]]; then
    echo $GREEN"Container $DOCKER_NAME successfully started"$RESET
  else
    echo $RED"Container $DOCKER_NAME didn't start!"$RESET
  fi
}

snapshot() {
  if [[ "$1" && "$2" ]]; then # $1 and $2 passed through the function
    curdir=$(pwd)
    case $1 in
    dump | load)
      stop
      docker run $DPORTS -v $SHM_DIR:/shm -v "$DATADIR":/hive -d --log-opt max-size=1g --log-opt max-file=1 -h $DOCKER_NAME --name $DOCKER_NAME -t hive:$TAG_VERSION hived --data-dir=/hive/witness_node_data_dir --$1-snapshot "$2"
      #logs # monitor the snapshot
      sleep 1
      if [[ $(docker inspect -f {{.State.Running}} $DOCKER_NAME) == true ]]; then
        echo $GREEN"Container $DOCKER_NAME successfully started"
        echo "Waiting for snapshot process to finish, you can ctrl-c this dialog and monitor it separately with: docker logs $DOCKER_NAME -f"$RESET
        until docker logs $DOCKER_NAME --tail=100 | grep --color=always -i "State snapshot.*(real)"; do sleep 1; done # wait for snapshot to finish
        # Get the block height and append it to the snapshot name (remove ANSI codes with sed and trim the line returns to get only the block number)
        #blockheight=$(docker logs $DOCKER_NAME | grep "Current block number" | awk '{ print $NF }' | sed -r 's/\x1b\[[0-9;]*m//g' | tr -d '\r\n')
        if [[ $1 == "dump" ]]; then
          blockheight=$(cat data/state_snapshot_dump.json | jq ".total_measurement.block_number") # less complicated
          today=$(date '+%Y%m%d')
          sudo mv "$DATADIR/witness_node_data_dir/snapshot/$2" "$DATADIR/witness_node_data_dir/snapshot/$2-$today-blockheight-$blockheight"
          echo $GREEN$"Snapshot block height  : $blockheight"$RESET
          echo $GREEN$"Snapshot size/location :" $(du -hs "$DATADIR/witness_node_data_dir/snapshot/$2-$today-blockheight-$blockheight")$RESET # get the size
        fi
      else
        echo $RED"Container $DOCKER_NAME didn't start!"$RESET
      fi
      ;;
    pack)
      if [[ -d "data/witness_node_data_dir/snapshot/$2" ]]; then
        echo $GREEN$"Packing snapshot '$2' to current folder"$RESET # get the size
        cd "data/witness_node_data_dir/snapshot"
        sudo tar czvf "$curdir/$2.tgz" "$2"
      else
        echo $RED"Snapshot $2 folder missing"$RESET
      fi
      ;;
    unpack)
      mkdir -p data/witness_node_data_dir/snapshot # create the folder if doesn't exist
      sudo tar xzvf "$curdir/$2.tgz" -C "data/witness_node_data_dir/snapshot/"
      ;;
    esac
  else
    echo $RED"Missing snapshot command and name, pass them as arguments, e.g. ./run.sh snapshot <dump, load, pack or unpack> snapshot_name"$RESET
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

save() {
  if [[ $SHM_DIR =~ "/dev/shm" ]]; then
    availablespace=$(df -P . | awk 'END{print $4}')
    filesize=$(du -k "$SHM_DIR/shared_memory.bin" | awk '{print $1}')
    echo "Available space ${availablespace}kb"
    echo "Shared memory size ${filesize}kb"
    if ((filesize > availablespace)); then
      echo "Not enough space to save"
    else
      stop
      rm $(pwd)/shared_memory.bin
      rsync -aAHXPh -v --stats /dev/shm/shared_memory.bin .
    fi
  else
    echo "SHM_DIR ($SHM_DIR) is not in tmpfs"
  fi
}

load() {
  sudo rm /dev/shm/shared_memory.bin
  rsync -aAHXPh -v --stats shared_memory.bin /dev/shm/
  start
}

compress() {
  stop
  mkdir -p $DATADIR/witness_node_data_dir/blockchain/compressed
  docker run $DPORTS -v $SHM_DIR:/shm -v "$DATADIR":/hive -d --log-opt max-size=1g --log-opt max-file=1 -h $DOCKER_NAME --name $DOCKER_NAME -t hive:$TAG_VERSION compress_block_log -j$(expr $(nproc) - 2) --benchmark-decompression -i /hive/witness_node_data_dir/blockchain -o /hive/witness_node_data_dir/blockchain/compressed
  logs
}

wallet() {
  docker exec -it $DOCKER_NAME cli_wallet
}

# Usage: ./run.sh remote_wallet [wss_server]
# Connects to a remote websocket server for wallet connection. This is completely safe
# as your wallet/private keys are never sent to the remote server.
#
# By default, it will connect to wss://api.deathwing.me:443 (ws = normal websockets, wss = secure HTTPS websockets)
# See this link for a list of WSS nodes: https://www.HIVE.center/index.php?title=Public_Websocket_Servers
#
#    wss_server - a custom websocket server to connect to, e.g. ./run.sh remote_wallet wss://rpc.HIVEviz.com
#
remote_wallet() {
  if (($# >= 1)); then
    REMOTE_WS="$1"
  fi
  docker run -v "$DATADIR":/hive --rm -it --name remote_wallet hive:$TAG_VERSION cli_wallet -s "$REMOTE_WS"
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
  start $2
  ;;
replay)
  replay $2
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
snapshot)
  snapshot $2 $3
  ;;
save)
  save
  ;;
load)
  load
  ;;
compress)
  compress
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
  remote_wallet $2
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
