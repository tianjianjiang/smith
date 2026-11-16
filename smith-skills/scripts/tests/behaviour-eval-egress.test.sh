#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../behaviour-eval-egress.sh"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

[ -f "$SCRIPT" ] || fail "smith-skills/scripts/behaviour-eval-egress.sh must exist"

mkdir -p "$TMPD/bin" "$TMPD/state"
FAKE_LOG="$TMPD/invocations.log"
FAKE_STATE="$TMPD/state"
export FAKE_LOG FAKE_STATE

cat > "$TMPD/bin/docker" <<'FAKE'
#!/bin/sh
echo "docker $*" >> "$FAKE_LOG"
case "$*" in
  *"network inspect bridge"*)
    echo "${FAKE_BRIDGE_IPV6:-false}"
    ;;
  ps*"network=bridge"*)
    [ -z "$FAKE_BRIDGE_CONTAINERS" ] || printf '%s\n' "$FAKE_BRIDGE_CONTAINERS"
    ;;
  ps*)
    [ -z "$FAKE_ALL_CONTAINERS" ] || printf '%s\n' "$FAKE_ALL_CONTAINERS"
    ;;
  run*getent*)
    printf '%s\n' "$FAKE_RESOLVED_OUTPUT"
    ;;
  run*)
    printf '%s\n' "$FAKE_PROBE_OUTPUT"
    ;;
esac
exit 0
FAKE

cat > "$TMPD/bin/rdctl" <<'FAKE'
#!/bin/sh
echo "rdctl $*" >> "$FAKE_LOG"
chain=SMITH-EGRESS
case "$*" in
  *"cat /etc/resolv.conf"*)
    echo "nameserver ${FAKE_VM_RESOLVER:-192.168.5.2}"
    ;;
  *"iptables"*"-C DOCKER-USER"*)
    [ -f "$FAKE_STATE/jump" ] || exit 1
    ;;
  *"iptables"*"-D DOCKER-USER"*)
    rm -f "$FAKE_STATE/jump"
    ;;
  *"iptables"*"-I DOCKER-USER"*)
    touch "$FAKE_STATE/jump"
    ;;
  *"iptables"*"-N $chain"*)
    touch "$FAKE_STATE/chain"
    ;;
  *"iptables"*"-X $chain"*)
    rm -f "$FAKE_STATE/chain"
    ;;
  *"iptables"*"-L $chain"*|*"iptables"*"-S $chain"*)
    [ -f "$FAKE_STATE/chain" ] || exit 1
    echo "-N $chain"
    ;;
esac
exit 0
FAKE
chmod +x "$TMPD/bin/docker" "$TMPD/bin/rdctl"

RESOLVED_VENDOR_FIRST="203.0.113.10"
RESOLVED_VENDOR_SECOND="203.0.113.11"
RESOLVED_REGISTRY="198.51.100.7"
RESOLVED_ADDRESSES="$RESOLVED_VENDOR_FIRST $RESOLVED_VENDOR_SECOND $RESOLVED_REGISTRY"
CHAIN=SMITH-EGRESS
VM_RESOLVER="198.18.0.53"
FAKE_VM_RESOLVER="$VM_RESOLVER"
export FAKE_VM_RESOLVER

set_probe() {
  FAKE_PROBE_OUTPUT="api.anthropic.com: $1
example.com: $2
www.google.com: $3
ipv6-literal: $4
foreign-host via $RESOLVED_VENDOR_FIRST: $5
foreign-host via $RESOLVED_VENDOR_SECOND: $5
foreign-host via $RESOLVED_REGISTRY: $5"
  export FAKE_PROBE_OUTPUT
}

reset_world() {
  : > "$FAKE_LOG"
  rm -f "$FAKE_STATE/chain" "$FAKE_STATE/jump"
  FAKE_BRIDGE_CONTAINERS=""
  FAKE_BRIDGE_IPV6="false"
  FAKE_ALL_CONTAINERS=""
  FAKE_RESOLVED_OUTPUT="$RESOLVED_VENDOR_FIRST STREAM api.anthropic.com
$RESOLVED_VENDOR_SECOND STREAM api.anthropic.com
$RESOLVED_VENDOR_FIRST STREAM api.anthropic.com
$RESOLVED_REGISTRY STREAM registry.npmjs.org"
  set_probe reachable blocked blocked blocked blocked
  export FAKE_BRIDGE_CONTAINERS FAKE_BRIDGE_IPV6 FAKE_ALL_CONTAINERS FAKE_RESOLVED_OUTPUT
}

run_egress() {
  rc=0
  PATH="$TMPD/bin:$PATH" sh "$SCRIPT" "$@" > "$TMPD/out" 2>&1 || rc=$?
}

chain_rule_has() {
  matches=$(grep -F -- "-A $CHAIN" "$FAKE_LOG")
  for fragment in "$@"; do
    matches=$(printf '%s\n' "$matches" | grep -F -- "$fragment")
  done
  [ -n "$matches" ]
}

installed_any_rule() { grep -Eq -- 'iptables.* -[AIN] ' "$FAKE_LOG"; }
removed_anything() { grep -Eq -- 'iptables.* -[DXF] ' "$FAKE_LOG"; }

reset_world
run_egress up
[ "$rc" = 0 ] || fail "up on a quiet bridge must succeed, got status $rc: $(cat "$TMPD/out")"
[ -f "$FAKE_STATE/chain" ] || fail "up on a quiet bridge must create the chain"
[ -f "$FAKE_STATE/jump" ] || fail "up on a quiet bridge must insert the jump into DOCKER-USER"
chain_rule_has "ESTABLISHED,RELATED" || fail "up must allow established flows"
chain_rule_has "-d $VM_RESOLVER" "-p udp" "--dport 53" || fail "up must allow DNS over udp to the VM resolver $VM_RESOLVER, read from the VM rather than hard-coded"
chain_rule_has "-d $VM_RESOLVER" "-p tcp" "--dport 53" || fail "up must allow DNS over tcp to the VM resolver $VM_RESOLVER, read from the VM rather than hard-coded"
other_dns=$(grep -F -- "-A $CHAIN" "$FAKE_LOG" | grep -F -- "--dport 53" | grep -vF -- "-d $VM_RESOLVER")
[ -z "$other_dns" ] || fail "up must allow DNS only to the VM resolver, got: $other_dns"
for address in $RESOLVED_ADDRESSES; do
  chain_rule_has "-d $address" "-p tcp" "--dport 443" || fail "up must allow tcp 443 to resolved address $address"
done
stray=$(grep -F -- "-A $CHAIN" "$FAKE_LOG" | grep -F -- "--dport 443")
for address in $RESOLVED_ADDRESSES; do
  stray=$(printf '%s\n' "$stray" | grep -vF -- "-d $address")
done
[ -z "$stray" ] || fail "up must open tcp 443 only to resolved addresses, got: $stray"
last_rule=$(grep -F -- "-A $CHAIN" "$FAKE_LOG" | tail -n 1)
case "$last_rule" in *"-j REJECT"*) ;; *) fail "the chain must end in a reject, got last rule: $last_rule" ;; esac
last_rule_line=$(grep -n -F -- "-A $CHAIN" "$FAKE_LOG" | tail -n 1 | cut -d: -f1)
jump_line=$(grep -n -- "-I DOCKER-USER" "$FAKE_LOG" | head -n 1 | cut -d: -f1)
[ -n "$jump_line" ] || fail "up must issue the jump insertion"
[ "$jump_line" -gt "$last_rule_line" ] || fail "the jump must be inserted only after the chain is complete"
grep -- "-I DOCKER-USER" "$FAKE_LOG" | grep -q -- "-i docker0" || fail "the jump must be inserted for the default bridge interface docker0"
grep -- "-I DOCKER-USER" "$FAKE_LOG" | grep -q -- "-j $CHAIN" || fail "the jump must target the chain"
grep -Eq -- ' -s .* -j RETURN' "$FAKE_LOG" && fail "up must never issue a source-address exemption"

reset_world
FAKE_BRIDGE_CONTAINERS="neighbour-one"
export FAKE_BRIDGE_CONTAINERS
run_egress up
[ "$rc" != 0 ] || fail "up must refuse while a container is attached to the default bridge"
installed_any_rule && fail "a refused up must install no rule"
grep -q "neighbour-one" "$TMPD/out" || fail "a refusal for an attached container must name it, got: $(cat "$TMPD/out")"
grep -Eq -- ' -s .* -j RETURN' "$FAKE_LOG" && fail "a refused up must not issue a source-address exemption"

reset_world
FAKE_BRIDGE_CONTAINERS="neighbour-one
neighbour-two"
export FAKE_BRIDGE_CONTAINERS
run_egress up
[ "$rc" != 0 ] || fail "up must refuse while several containers are attached to the default bridge"
grep -q "neighbour-one" "$TMPD/out" || fail "a refusal must name the first attached container, got: $(cat "$TMPD/out")"
grep -q "neighbour-two" "$TMPD/out" || fail "a refusal must name every attached container, got: $(cat "$TMPD/out")"
installed_any_rule && fail "a refused up with several containers must install no rule"

reset_world
FAKE_BRIDGE_IPV6="true"
export FAKE_BRIDGE_IPV6
run_egress up
[ "$rc" != 0 ] || fail "up must refuse when the default bridge has IPv6 enabled"
installed_any_rule && fail "an up refused for IPv6 must install no rule"
[ -f "$FAKE_STATE/chain" ] && fail "an up refused for IPv6 must leave no chain behind"
[ -s "$TMPD/out" ] || fail "an up refused for IPv6 must say why"

reset_world
run_egress probe
[ "$rc" = 0 ] || fail "probe must pass when the API is reachable and every other target is blocked, got status $rc: $(cat "$TMPD/out")"
grep -q "^api.anthropic.com: reachable$" "$TMPD/out" || fail "probe must print the vendor API line"
grep -q "^example.com: blocked$" "$TMPD/out" || fail "probe must print the first non-allowed host line"
grep -q "^www.google.com: blocked$" "$TMPD/out" || fail "probe must print the second non-allowed host line"
grep -q "^ipv6-literal: blocked$" "$TMPD/out" || fail "probe must print the IPv6 literal line"
for address in $RESOLVED_ADDRESSES; do
  grep -q "^foreign-host via $address: blocked$" "$TMPD/out" || fail "probe must print a foreign-host line for allowed address $address"
  grep -v getent "$FAKE_LOG" | grep -F -- "docker run" | grep -qF -- "$address" || fail "the probe container must be told allowed address $address"
done

reset_world
set_probe unreachable blocked blocked blocked blocked
run_egress probe
[ "$rc" != 0 ] || fail "probe must fail when the vendor API is not reachable"

reset_world
set_probe reachable reachable blocked blocked blocked
run_egress probe
[ "$rc" != 0 ] || fail "probe must fail when the first non-allowed host is reachable"

reset_world
set_probe reachable blocked reachable blocked blocked
run_egress probe
[ "$rc" != 0 ] || fail "probe must fail when the second non-allowed host is reachable"

reset_world
set_probe reachable blocked blocked reachable blocked
run_egress probe
[ "$rc" != 0 ] || fail "probe must fail when the IPv6 literal is reachable"

reset_world
set_probe reachable blocked blocked blocked reachable
run_egress probe
[ "$rc" = 0 ] || fail "a reachable foreign host through an allowed address is a recorded residual and must not fail the gate, got status $rc: $(cat "$TMPD/out")"
for address in $RESOLVED_ADDRESSES; do
  grep -q "^foreign-host via $address: reachable$" "$TMPD/out" || fail "probe must record foreign-host reachable via $address"
done

reset_world
FAKE_PROBE_OUTPUT="api.anthropic.com: reachable
www.google.com: blocked
ipv6-literal: blocked"
export FAKE_PROBE_OUTPUT
run_egress probe
[ "$rc" != 0 ] || fail "probe must fail when a non-allowed target produced no line, a missing signal never passes"

reset_world
FAKE_PROBE_OUTPUT=""
export FAKE_PROBE_OUTPUT
run_egress probe
[ "$rc" != 0 ] || fail "probe must fail when the probe container printed nothing"

reset_world
touch "$FAKE_STATE/chain" "$FAKE_STATE/jump"
run_egress status
[ "$rc" = 0 ] || fail "status must exit 0 while the chain exists, got status $rc"
grep -q "chain present" "$TMPD/out" || fail "status must print chain present while the chain exists, got: $(cat "$TMPD/out")"
grep -q "chain absent" "$TMPD/out" && fail "status must not print chain absent while the chain exists"
installed_any_rule && fail "status must not install any rule"
removed_anything && fail "status must not remove anything"

reset_world
run_egress status
[ "$rc" = 1 ] || fail "status must exit 1 while the chain is absent, got status $rc"
grep -q "chain absent" "$TMPD/out" || fail "status must print chain absent while the chain is absent, got: $(cat "$TMPD/out")"
grep -q "chain present" "$TMPD/out" && fail "status must not print chain present while the chain is absent"

reset_world
touch "$FAKE_STATE/chain" "$FAKE_STATE/jump"
FAKE_ALL_CONTAINERS="skilled-run-one"
export FAKE_ALL_CONTAINERS
run_egress down
[ "$rc" != 0 ] || fail "down must refuse while a skilled- container exists"
removed_anything && fail "a refused down must remove nothing"
[ -f "$FAKE_STATE/chain" ] || fail "a refused down must leave the chain in place"
[ -f "$FAKE_STATE/jump" ] || fail "a refused down must leave the jump in place"
grep -q "skilled-run-one" "$TMPD/out" || fail "a refused down must name the container, got: $(cat "$TMPD/out")"

reset_world
touch "$FAKE_STATE/chain" "$FAKE_STATE/jump"
FAKE_ALL_CONTAINERS="unrelated-box
unskilled-box"
export FAKE_ALL_CONTAINERS
run_egress down
[ "$rc" = 0 ] || fail "down must proceed when no container name starts with skilled-, got status $rc: $(cat "$TMPD/out")"
[ -f "$FAKE_STATE/chain" ] && fail "down must remove the chain"
[ -f "$FAKE_STATE/jump" ] && fail "down must remove the jump"

reset_world
touch "$FAKE_STATE/chain" "$FAKE_STATE/jump"
run_egress down
[ "$rc" = 0 ] || fail "down with no containers must succeed, got status $rc: $(cat "$TMPD/out")"
[ -f "$FAKE_STATE/chain" ] && fail "down with no containers must remove the chain"
[ -f "$FAKE_STATE/jump" ] && fail "down with no containers must remove the jump"

reset_world
run_egress down
[ "$rc" = 0 ] || fail "down must be safe when no chain exists, got status $rc: $(cat "$TMPD/out")"

reset_world
run_egress unknown-subcommand
[ "$rc" = 2 ] || fail "an unknown subcommand must exit 2, got status $rc"
grep -qi "usage" "$TMPD/out" || fail "an unknown subcommand must print a usage line, got: $(cat "$TMPD/out")"
installed_any_rule && fail "an unknown subcommand must install no rule"

echo "PASS: behaviour-eval-egress"
