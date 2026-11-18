#!/bin/sh
set -eu

usage="usage: behaviour-eval-egress.sh up|down|status|probe"
chain=SMITH-EGRESS
bridge_interface=docker0
allowed_hosts="api.anthropic.com registry.npmjs.org"
probe_image=node:24-bookworm-slim
container_prefix=skilled-

die() {
  echo "egress: $1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "$1 was not found on PATH"
}

vm() {
  rdctl shell sudo "$@"
}

chain_exists() {
  vm iptables -n -L "$chain" >/dev/null 2>&1
}

jump_exists() {
  vm iptables -C DOCKER-USER -i "$bridge_interface" -j "$chain" >/dev/null 2>&1
}

bridge_containers() {
  docker ps --filter network=bridge --format '{{.Names}}'
}

skilled_containers() {
  names=$(docker ps -a --format '{{.Names}}') || die "docker could not list the containers; the chain stays in place"
  printf '%s\n' "$names" | grep "^$container_prefix" || true
}

vm_resolver() {
  rdctl shell cat /etc/resolv.conf | awk '$1 == "nameserver" && $2 ~ /^[0-9.]+$/ { print $2; exit }'
}

resolve_allowed_addresses() {
  docker run --rm --network bridge "$probe_image" \
    sh -c "for host in $allowed_hosts; do getent ahostsv4 \"\$host\"; done" \
    | awk '{ print $1 }' | LC_ALL=C sort -u | tr '\n' ' '
}

bridge_ipv6_enabled() {
  [ "$(docker network inspect bridge --format '{{.EnableIPv6}}')" = true ]
}

up() {
  chain_exists && die "refused: the chain $chain already exists, run down first"
  attached=$(bridge_containers)
  [ -z "$attached" ] || die "refused: a container is attached to the default bridge, which the chain would filter: $attached"
  bridge_ipv6_enabled && die "refused: the default bridge has IPv6 enabled, which the chain does not filter"
  resolver=$(vm_resolver)
  [ -n "$resolver" ] || die "no VM resolver address was found in the VM resolv.conf"
  addresses=$(resolve_allowed_addresses)
  [ -n "$addresses" ] || die "no address resolved for $allowed_hosts"
  vm iptables -N "$chain"
  vm iptables -A "$chain" -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
  vm iptables -A "$chain" -d "$resolver" -p udp --dport 53 -j RETURN
  vm iptables -A "$chain" -d "$resolver" -p tcp --dport 53 -j RETURN
  for address in $addresses; do
    vm iptables -A "$chain" -d "$address" -p tcp --dport 443 -j RETURN
    echo "allow $address:443"
  done
  vm iptables -A "$chain" -j REJECT
  vm iptables -I DOCKER-USER 1 -i "$bridge_interface" -j "$chain"
  echo "egress: up"
}

down() {
  remaining=$(skilled_containers)
  [ -z "$remaining" ] || die "refused: containers named $container_prefix* still exist: $remaining"
  while jump_exists; do
    vm iptables -D DOCKER-USER -i "$bridge_interface" -j "$chain"
  done
  if chain_exists; then
    vm iptables -F "$chain"
    vm iptables -X "$chain"
  fi
  echo "egress: down"
}

status() {
  if chain_exists; then
    echo "chain present"
  else
    echo "chain absent"
    exit 1
  fi
}

probe_program='
const https = require("https");
const allowed = (process.env.ALLOWED_ADDRESSES || "").split(" ").filter(Boolean);
const attempt = (label, options) => new Promise((done) => {
  const request = https.request({ method: "GET", path: "/", timeout: 8000, rejectUnauthorized: false, ...options }, (response) => {
    response.resume();
    done(label + ": reachable");
  });
  request.on("timeout", () => { request.destroy(); done(label + ": blocked"); });
  request.on("error", () => done(label + ": blocked"));
  request.end();
});
const targets = [
  attempt("api.anthropic.com", { host: "api.anthropic.com", path: "/v1/models" }),
  attempt("example.com", { host: "example.com" }),
  attempt("www.google.com", { host: "www.google.com" }),
  attempt("ipv6-literal", { host: "2606:4700:4700::1111", family: 6 }),
  ...allowed.map((address) => attempt("foreign-host via " + address, { host: address, servername: "example.com", headers: { Host: "example.com" } })),
];
Promise.all(targets).then((lines) => console.log(lines.join("\n")));
'

probe() {
  addresses=$(resolve_allowed_addresses)
  [ -n "$addresses" ] || die "no address resolved for $allowed_hosts"
  output=$(docker run --rm --network bridge -e "ALLOWED_ADDRESSES=$addresses" "$probe_image" node -e "$probe_program") \
    || die "the probe container failed to run"
  printf '%s\n' "$output"
  verdict=0
  printf '%s\n' "$output" | grep -Fxq "api.anthropic.com: reachable" || {
    echo "egress: the vendor API is not reachable or produced no line" >&2
    verdict=1
  }
  for target in example.com www.google.com ipv6-literal; do
    printf '%s\n' "$output" | grep -Fxq "$target: blocked" || {
      echo "egress: $target is not reported blocked" >&2
      verdict=1
    }
  done
  exit "$verdict"
}

[ $# -eq 1 ] || { echo "$usage" >&2; exit 2; }

case "$1" in
  up | down | status | probe) ;;
  *) echo "$usage" >&2; exit 2 ;;
esac

require_command docker
require_command rdctl

case "$1" in
  up) up ;;
  down) down ;;
  status) status ;;
  probe) probe ;;
esac
