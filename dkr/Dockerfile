FROM ubuntu:xenial

#ARG steemd_version=master
ARG steemd_version
RUN echo "Building steemd version: ${steemd_version}"

RUN apt-get update
# Required packages
RUN apt-get install -y autoconf automake cmake g++ git libbz2-dev libsnappy-dev libssl-dev libtool make pkg-config python3 python3-jinja2

# Boost packages
RUN apt-get install -y libboost-chrono-dev libboost-context-dev libboost-coroutine-dev libboost-date-time-dev libboost-filesystem-dev libboost-iostreams-dev libboost-locale-dev libboost-program-options-dev libboost-serialization-dev libboost-signals-dev libboost-system-dev libboost-test-dev libboost-thread-dev

# Optional packages
RUN apt-get install -y doxygen libncurses5-dev libreadline-dev perl

# Other useful packages
RUN apt-get install -y curl nano wget

RUN apt-get clean -qy

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
	mkdir build && cd build && \
	cmake -DCMAKE_BUILD_TYPE=Release .. -DLOW_MEMORY_NODE=ON -DCLEAR_VOTES=ON -DSKIP_BY_TX_ID=ON && \
	make -j$(nproc) && \
	make install && cd .. && rm -rf build # defaults to /usr/bin
VOLUME /steem
WORKDIR /steem

RUN echo "Please configure me! You need to mount a data directory onto /steem of this container to it to function correctly. (if you're using Steem-in-a-box most of this is handled automatically)"
CMD ["sh", "-c", "/usr/bin/steemd"]
