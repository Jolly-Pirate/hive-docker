FROM ubuntu:xenial

RUN apt-get update  && \
	# Required packages
	apt-get install -y autoconf automake cmake g++ git libbz2-dev libsnappy-dev libssl-dev libtool make pkg-config python3 python3-jinja2  && \
	# Boost packages
	apt-get install -y libboost-chrono-dev libboost-context-dev libboost-coroutine-dev libboost-date-time-dev libboost-filesystem-dev libboost-iostreams-dev libboost-locale-dev libboost-program-options-dev libboost-serialization-dev libboost-signals-dev libboost-system-dev libboost-test-dev libboost-thread-dev  && \
	# Optional packages
	apt-get install -y doxygen libncurses5-dev libreadline-dev perl  && \
	# Other useful packages
	apt-get install -y curl nano wget  && \
	apt-get clean -qy
