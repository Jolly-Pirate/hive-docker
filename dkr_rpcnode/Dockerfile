#FROM ubuntu:xenial
FROM steem-pkg

ARG steemd_version

RUN echo "Building steemd version: ${steemd_version}"

# P2P (seed) port
EXPOSE 2001
# RPC ports
EXPOSE 5000
EXPOSE 8090

RUN cd ~ && \
	git clone https://github.com/steemit/steem.git && \
	cd steem && \
	git checkout ${steemd_version} && \
	git submodule update --init --recursive && \
	# fix Websocket Timer Expired, just in case. https://github.com/steemit/steem/issues/35
	sed -i libraries/fc/vendor/websocketpp/websocketpp/transport/asio/endpoint.hpp -e 's/m_listen_backlog(0)/m_listen_backlog(lib::asio::socket_base::max_connections)/g' && \
	mkdir build && cd build && \
	cmake -DCMAKE_BUILD_TYPE=Release .. -DLOW_MEMORY_NODE=OFF -DCLEAR_VOTES=OFF -DSKIP_BY_TX_ID=OFF && \
	make -j$(nproc) && \
	make install && cd .. && rm -rf build # install defaults to /usr/bin

VOLUME /steem
WORKDIR /steem

RUN echo "Please configure me! You need to mount a data directory onto /steem of this container to it to function correctly. (if you're using Steem-in-a-box most of this is handled automatically)"
CMD ["sh", "-c", "/usr/bin/steemd"]
