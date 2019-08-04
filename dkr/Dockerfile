# An ARG declared before a FROM is outside of a build stage, so it can?t be used in any instruction after a FROM.
ARG BUILD_OS
FROM ${BUILD_OS}

ARG BUILD_OS
ARG STEEM_VERSION
ARG BUILD_SWITCHES

RUN echo "\033[1mInstalling packages (ctrl-c to cancel)\033[0m" && \
    echo "Building $STEEM_VERSION image in $BUILD_OS" && \
	if echo $BUILD_SWITCHES | grep -q "MIRA=ON" ; then echo "Building with MIRA=ON";fi && \
	sleep 5 && \
	apt-get update && \
	apt-get install -y bc curl nano net-tools wget jq \
    autoconf automake autotools-dev bsdmainutils build-essential cmake doxygen gdb git libboost-all-dev libyajl-dev \
    libreadline-dev libssl-dev libtool liblz4-tool ncurses-dev pkg-config python3 python3-dev python3-jinja2 python3-pip virtualenv \
    libgflags-dev libsnappy-dev zlib1g-dev libbz2-dev liblz4-dev libzstd-dev && \
	# ubuntu 18.04 moved to openssl 1.1.1 causing too much problems, downgrading to 1.1.0g
    #if openssl version | grep -q 1.1.1; then apt-get install -y --allow-downgrades openssl=1.1.0g-2ubuntu4.3 libssl1.1=1.1.0g-2ubuntu4.3 libssl-dev=1.1.0g-2ubuntu4.3; fi &&
	#openssl version ; sleep 5 &&
	apt-get clean -qy

RUN echo "\033[1mBuilding steemd version: ${STEEM_VERSION} with ${BUILD_SWITCHES} (ctrl-c to cancel)\033[0m" && \
	sleep 5 && \
	cd ~ && \
	git clone https://github.com/steemit/steem.git && \
	cd steem && \
	git checkout ${STEEM_VERSION} && \
    # anyx fix for Unlinkable block p2p, merged Jan 7, 2019
	#curl https://github.com/steemit/steem/commit/e66af33329e35a91ddf42abd6529b4bbdd9f7ec8.patch | git apply &&
    # 20.12/21.0 patch for https://github.com/steemit/steem/issues/3441
    #git cherry-pick 3308eb8d8f1a773536a5b08db33616786e58a4ca &&
    # cherry-pick works only when a github account is setup on the machine
    curl https://github.com/steemit/steem/commit/3308eb8d8f1a773536a5b08db33616786e58a4ca.patch | git apply && \
	# fix static building
	curl https://github.com/steemit/steem/commit/99ea30f88eecc8116ccdbeae8ca4911bf1738b5a.patch | git apply && \
	git submodule update --init --recursive && \
	# fix boost version
	# curl https://github.com/steemit/steem/commit/89b5725ea32f90a7927d00491c678802e55e8d8a.patch | git apply &&
	# Link Boost after OpenSSL (fix for openssl 1.1.1), https://github.com/steemit/steem/issues/3352
	#if openssl version | grep -q 1.1.1; then curl https://github.com/steemit/steem/commit/8e2e0f774332b9e6a2d3942ceb3e707bcc5867b2.patch | git apply; fi &&
	# fix Websocket Timer Expired, just in case. https://github.com/steemit/steem/issues/35
	sed -i libraries/fc/vendor/websocketpp/websocketpp/transport/asio/endpoint.hpp -e 's/m_listen_backlog(0)/m_listen_backlog(lib::asio::socket_base::max_connections)/g' && \
	mkdir build && cd build && \
	cmake -DCMAKE_BUILD_TYPE=Release .. ${BUILD_SWITCHES} && \
	# https://github.com/steemit/steem/issues/3369#issuecomment-505525258 temporary fix for 0.20.11 on bionic
	#if echo $BUILD_SWITCHES | grep -q "MIRA=ON"; then make -j$(nproc); else make -j$(nproc) steemd && make -j$(nproc) cli_wallet; fi &&
	make -j`echo $(nproc)-2 | bc` && \
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
