time docker stop witness -t 600
while [[ $(docker inspect -f {{.State.Running}} witness) == true ]]
do
  echo -e "\e[0;35mWaiting for container to stop cleanly\e[0m"
  sleep 0.1
done
docker logs witness --tail=8
