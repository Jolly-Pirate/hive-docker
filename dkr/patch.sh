#!/usr/bin/env bash

echo -e "\033[1mApplying custom patches\033[0m"
 # anyx fix for Unlinkable block p2p, merged Jan 7, 2019
#curl https://github.com/steemit/steem/commit/e66af33329e35a91ddf42abd6529b4bbdd9f7ec8.patch | git apply &&
# 20.12/21.0 patch for https://github.com/steemit/steem/issues/3441
#git cherry-pick 3308eb8d8f1a773536a5b08db33616786e58a4ca &&
# cherry-pick works only when a github account is setup on the machine
#curl https://github.com/steemit/steem/commit/3308eb8d8f1a773536a5b08db33616786e58a4ca.patch | git apply &&
# fix boost version
# curl https://github.com/steemit/steem/commit/89b5725ea32f90a7927d00491c678802e55e8d8a.patch | git apply &&
# Link Boost after OpenSSL (fix for openssl 1.1.1), https://github.com/steemit/steem/issues/3352
#if openssl version | grep -q 1.1.1; then curl https://github.com/steemit/steem/commit/8e2e0f774332b9e6a2d3942ceb3e707bcc5867b2.patch | git apply; fi &&
# fix Websocket Timer Expired, just in case. https://github.com/steemit/steem/issues/35
sed -i libraries/fc/vendor/websocketpp/websocketpp/transport/asio/endpoint.hpp -e 's/m_listen_backlog(0)/m_listen_backlog(lib::asio::socket_base::max_connections)/g' && \
# curl https://github.com/steemit/steem/commit/53392cc31f011f9a8def8dfffff78dbab17ebf2e.patch  | git apply # already applied in 0.22.2

# disable logging not_enough_rc_exception to the console
git cherry-pick d40879068a357ffd789b8743122801341de36b3a

sleep 5
