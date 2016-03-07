#!/usr/bin/env bash

# bomb on any error
set -e

BUILD_ROOT=/opt/netflix-proxy
SDNS_ADMIN_PORT=43867
IFACE=$(ip route | grep default | awk '{print $5}')
IPADDR=$(ip addr show dev ${IFACE} | \
  grep inet | \
  grep -v inet6 | \
  awk '{print $2}' | \
  grep -Po '[0-9]{1,3}+\.[0-9]{1,3}+\.[0-9]{1,3}+\.[0-9]{1,3}+(?=\/)')

RDNS=$(echo ${IPADDR} | awk '{print $1}' | xargs dig +short -x)

if [[ -z "${RDNS}" ]]; then
	RDNS=$(echo ${IPADDR} | awk '{print $1}')
fi

echo "Configuring Caddy"
$(which sed) "s/{{RDNS}}/${RDNS}/" ${BUILD_ROOT}/Caddyfile.template | sudo tee ${BUILD_ROOT}/Caddyfile
printf "proxy /netflix-proxy/admin/ localhost:${SDNS_ADMIN_PORT} {\n\texcept /static\n\tproxy_header Host {host}\n\tproxy_header X-Forwarded-For {remote}\n\tproxy_header X-Real-IP {remote}\n\tproxy_header X-Forwarded-Proto {scheme}\n}\n" | sudo tee -a ${BUILD_ROOT}/Caddyfile

echo "Creating and starting Docker containers"
sudo BUILD_ROOT=${BUILD_ROOT} $(which docker-compose) -f ${BUILD_ROOT}/docker-compose/reverse-proxy.yaml up -d

if [[ `/sbin/init --version` =~ upstart ]]; then
	echo "Configuring upstart init system"
	sudo cp ${BUILD_ROOT}/upstart/sdns-admin.conf /etc/init/ && \
          sudo service docker-caddy start && \
          sudo service sdns-admin start
elif [[ `systemctl` =~ -\.mount ]]; then
	echo "Configuring systemd init system"
	sudo cp ${BUILD_ROOT}/systemd/sdns-admin.service /lib/systemd/system/ && \
          sudo systemctl daemon-reload && \
	  sudo systemctl enable docker-caddy && \
          sudo systemctl enable sdns-admin && \
          sudo systemctl start docker-caddy && \
          sudo systemctl start sdns-admin
fi

echo "Waiting 10 seconds for Caddy to start.."
sleep 10
curl -I http://localhost:${SDNS_ADMIN_PORT}/
curl -I https://${RDNS}/
