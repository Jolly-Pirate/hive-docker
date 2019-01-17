FROM ubuntu:xenial

RUN echo "\033[1mInstalling packages (ctrl-c to cancel)\033[0m" && \
	sleep 5 && \
	apt-get update && \
	# Required packages
	apt-get install -y autoconf automake cmake g++ git libbz2-dev libsnappy-dev libssl-dev libtool make pkg-config python3 python3-jinja2 && \
	# Boost packages (also required)
	apt-get install -y libboost-chrono-dev libboost-context-dev libboost-coroutine-dev libboost-date-time-dev libboost-filesystem-dev libboost-iostreams-dev libboost-locale-dev libboost-program-options-dev libboost-serialization-dev libboost-signals-dev libboost-system-dev libboost-test-dev libboost-thread-dev && \
	# Optional packages (not required, but will make a nicer experience)
	apt-get install -y doxygen libncurses5-dev libreadline-dev perl && \
	# Other useful packages
	apt-get install -y curl nano net-tools wget && \
	apt-get clean -qy

# P2P (seed) port
EXPOSE 2001
# RPC ports
EXPOSE 5000
EXPOSE 8090

ARG STEEM_VERSION
ARG BUILD_SWITCHES

RUN echo "\033[1mBuilding steemd version: ${STEEM_VERSION} with ${BUILD_SWITCHES} (ctrl-c to cancel)\033[0m" && \
	sleep 5 && \
	cd ~ && \
	git clone https://github.com/steemit/steem.git && \
	cd steem && \
	git checkout ${STEEM_VERSION} && \
    # anyx fix for Unlinkable block p2p
    curl https://github.com/steemit/steem/commit/e66af33329e35a91ddf42abd6529b4bbdd9f7ec8.patch | git apply && \
	git submodule update --init --recursive && \
	# fix Websocket Timer Expired, just in case. https://github.com/steemit/steem/issues/35
	sed -i libraries/fc/vendor/websocketpp/websocketpp/transport/asio/endpoint.hpp -e 's/m_listen_backlog(0)/m_listen_backlog(lib::asio::socket_base::max_connections)/g' && \
	mkdir build && cd build && \
	cmake -DCMAKE_BUILD_TYPE=Release .. ${BUILD_SWITCHES} && \
	make -j$(nproc) && \
	# install defaults to /usr/bin
	make install && cd .. && rm -rf build && \
	echo "\033[1mPlease configure me! You need to mount a data directory onto /steem of this container to it to function correctly. (if you're using Steem-in-a-box most of this is handled automatically)\033[0m"

VOLUME /steem
WORKDIR /steem

CMD ["sh", "-c", "/usr/bin/steemd"]
