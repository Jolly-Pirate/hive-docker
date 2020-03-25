# An ARG declared before a FROM is outside of a build stage, so it can?t be used in any instruction after a FROM.
ARG BUILD_OS
FROM ${BUILD_OS}

ARG BUILD_OS
ARG BUILD_VERSION
ARG BUILD_SWITCHES
ARG REPO_SOURCE

ADD patch.sh /

RUN echo "\033[1mInstalling packages (ctrl-c to cancel)\033[0m" && \
    echo "Building $BUILD_VERSION image in $BUILD_OS from $REPO_SOURCE" && \
	if echo $BUILD_SWITCHES | grep -q "MIRA=ON" ; then echo "Building with MIRA=ON";fi && \
	sleep 5 && \
	apt-get update && \
	apt-get install -y curl nano net-tools wget jq \
    autoconf automake autotools-dev bsdmainutils build-essential cmake doxygen gdb git libboost-all-dev libyajl-dev \
    libreadline-dev libssl-dev libtool liblz4-tool ncurses-dev pkg-config python3 python3-dev python3-jinja2 python3-pip virtualenv \
    libgflags-dev libsnappy-dev zlib1g-dev libbz2-dev liblz4-dev libzstd-dev && \
	# ubuntu 18.04 moved to openssl 1.1.1 causing too much problems, downgrading to 1.1.0g
    #if openssl version | grep -q 1.1.1; then apt-get install -y --allow-downgrades openssl=1.1.0g-2ubuntu4.3 libssl1.1=1.1.0g-2ubuntu4.3 libssl-dev=1.1.0g-2ubuntu4.3; fi &&
	#openssl version ; sleep 5 &&
	apt-get clean -qy

RUN echo "\033[1mBuilding steemd version: ${BUILD_VERSION} with ${BUILD_SWITCHES} (ctrl-c to cancel)\033[0m" && \
	sleep 5 && \
	cd ~ && \
	git clone ${REPO_SOURCE} clonedir && \
	cd clonedir && \
	git checkout ${BUILD_VERSION} && \
	git submodule update --init --recursive && \
	# apply the custom patches
	/patch.sh && \
	mkdir build && cd build && \
	cmake -DCMAKE_BUILD_TYPE=Release .. ${BUILD_SWITCHES} && \
	# https://github.com/steemit/steem/issues/3369#issuecomment-505525258 temporary fix for 0.20.11 on bionic
	#if echo $BUILD_SWITCHES | grep -q "MIRA=ON"; then make -j$(nproc); else make -j$(nproc) steemd && make -j$(nproc) cli_wallet; fi &&
	make -j`expr $(nproc) - 2` && \
	# install defaults to /usr/bin
	make install && cd .. && rm -rf build && \
	echo "\033[1mPlease configure me! You need to mount a data directory onto /steem of this container to it to function correctly. (if you're using Steem-in-a-box most of this is handled automatically)\033[0m"

# P2P (seed) port
EXPOSE 2001
# RPC ports
EXPOSE 5000
EXPOSE 8090

VOLUME /steem
WORKDIR /steem

CMD ["sh", "-c", "/usr/bin/steemd"]
