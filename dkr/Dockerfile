# syntax=docker/dockerfile:latest
# Stage 1
# An ARG declared before a FROM is outside of a build stage, so it can't be used in any instruction after a FROM.
ARG BUILD_OS
FROM ${BUILD_OS} as build

ARG BUILD_OS
ARG BUILD_VERSION
ARG BUILD_SWITCHES
ARG REPO_SOURCE

ADD patch.sh /

ENV LANG=en_US.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

RUN <<EOF
echo "Installing packages (ctrl-c to cancel)"
sleep 5
apt-get update
apt-get install -y curl nano net-tools wget jq tzdata \
autoconf automake autotools-dev bsdmainutils build-essential cmake doxygen gdb git libboost-all-dev libyajl-dev \
libreadline-dev libssl-dev libtool liblz4-tool ncurses-dev pkg-config python3 python3-dev python3-jinja2 python3-pip virtualenv \
libgflags-dev libsnappy-dev zlib1g-dev libbz2-dev liblz4-dev libzstd-dev ninja-build
apt-get clean -qy
EOF

RUN <<EOF
echo "Building hived $BUILD_VERSION in $BUILD_OS from $REPO_SOURCE (ctrl-c to cancel)"
sleep 5
cd ~
git clone ${REPO_SOURCE} clonedir
cd clonedir
git checkout ${BUILD_VERSION}
git submodule update --init --recursive
# apply the custom patches
/patch.sh
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -GNinja .. $BUILD_SWITCHES
ninja
#make -j`expr $(nproc) - 2`
# install defaults to /usr/bin
#ninja install
DESTDIR=/output ninja install
#cd .. && rm -rf build
EOF

RUN <<EOF
echo "Total size of built binaries"
du -hs /output/usr/bin
sleep 5
EOF

# Stage 2
FROM ${BUILD_OS}
#COPY --from=build /output /
COPY --from=build /output/usr/bin /usr/bin/

# P2P (seed) port
EXPOSE 2001
# RPC ports
EXPOSE 5000
EXPOSE 8090

VOLUME /hive
WORKDIR /hive

# commented, passing hived from the run.sh anyways
# CMD ["sh", "-c", "/usr/bin/hived"]
