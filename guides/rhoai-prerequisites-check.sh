#!/usr/bin/env bash
# RHOAI 3.4 — Phase 0 Cluster Prerequisites Check
# Automates Phase 0 validation from the installation field guide.
# Run as a cluster-admin (preferably not kubeadmin): bash guides/rhoai-prerequisites-check.sh
#
# Options:
#   -h, --help   Show usage

set -euo pipefail

HR="────────────────────────────────────────────────────────────────────"

usage() {
  cat <<'EOF'
RHOAI 3.4 — Phase 0 Cluster Prerequisites Check

Usage: bash guides/rhoai-prerequisites-check.sh

Checks cluster version, workers, default StorageClass, OAuth IdPs, ODH absence,
and registry/CDN reachability from a worker node (via oc debug).

Network check failures are reported as warnings (non-blocking) since registries
may require a proxy in some environments. All other failures are blocking.

Run as cluster-admin (preferably not kubeadmin). See guides/rhoai-34-install-field-guide.md
EOF
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift || true
done

row() { printf "  %-50s %s\n" "$1" "$2"; }

# ── cpu_to_millicores ─────────────────────────────────────────────────────────
cpu_to_millicores() {
  local c="${1:-0}"
  if [[ "$c" == *m ]]; then
    echo "${c%m}"
  else
    echo $((c * 1000))
  fi
}

# ── mem_to_ki ─────────────────────────────────────────────────────────────────
# Parses Kubernetes quantity ending in Ki, Mi, Gi, or bare bytes (best-effort).
mem_to_ki() {
  local q="${1:-0}"
  case "$q" in
    *Ki) echo "${q%%Ki}" ;;
    *Mi) echo $((${q%%Mi} * 1024)) ;;
    *Gi) echo $((${q%%Gi} * 1024 * 1024)) ;;
    *) echo 0 ;;
  esac
}

# ── http_code_from_node ───────────────────────────────────────────────────────
# Returns HTTP status code from curl on a worker via oc debug, or CURL_ERROR.
http_code_from_node() {
  local node="$1" url="$2"
  local out
  # oc debug may mix status lines with curl output — take last 3-digit HTTP code.
  out=$(oc debug "node/$node" -- chroot /host curl -sS -o /dev/null -w '%{http_code}' \
        --connect-timeout 15 --max-time 45 "$url" 2>&1) || true
  code=$(echo "$out" | grep -oE '[0-9]{3}' | tail -1)
  if echo "$out" | grep -q 'Could not resolve host'; then
    echo "DNS_FAIL"
  elif echo "$out" | grep -qE 'curl: \(7\)'; then
    echo "CONN_FAIL"
  elif [ -n "$code" ]; then
    echo "$code"
  else
    echo "CURL_ERROR"
  fi
}

FAILURES=0
WARNINGS=0
fail() { FAILURES=$((FAILURES + 1)); }
warn() { WARNINGS=$((WARNINGS + 1)); }

echo ""
echo "$HR"
echo "  RHOAI 3.4 — Phase 0 Cluster Prerequisites Check"
echo "  $(date)"
echo "$HR"

if ! command -v oc >/dev/null 2>&1; then
  echo ""
  echo "  ✗ oc not found in PATH"
  exit 1
fi

if ! oc whoami >/dev/null 2>&1; then
  echo ""
  echo "  ✗ Not logged in to a cluster (run: oc login ...)"
  exit 1
fi

echo ""
echo "CLUSTER & ACCESS"
echo "$HR"

ME=$(oc whoami 2>/dev/null || echo "")
row "Current user" "$ME"
if [ "$ME" = "kube:admin" ] || [ "$ME" = "kubeadmin" ]; then
  row "Non-kubeadmin admin" "⚠ WARN  (guide recommends a non-kubeadmin cluster-admin for installs)"
else
  row "Non-kubeadmin admin" "✓ OK  (not kubeadmin)"
fi

CAN=$(oc auth can-i '*' '*' --all-namespaces 2>/dev/null || echo "no")
if [ "$CAN" = "yes" ]; then
  row "Cluster-admin capability" "✓ OK"
else
  row "Cluster-admin capability" "✗ FAIL  (need cluster-admin; got: $CAN)"
  fail
fi

ver=""
# Current version is typically history[0]; during upgrades desiredUpdate.version may be set first.
ver=$(oc get clusterversion version -o jsonpath='{.status.history[0].version}' 2>/dev/null || true)
if [ -z "$ver" ]; then
  ver=$(oc get clusterversion version -o jsonpath='{.status.desiredUpdate.version}' 2>/dev/null || true)
fi
row "Cluster version" "${ver:-unknown}"

if [ -n "$ver" ]; then
  IFS=. read -r maj min _rest <<< "$ver"
  maj=${maj:-0}
  min=${min:-0}
  ok=0
  if [ "$maj" -gt 4 ]; then ok=1; fi
  if [ "$maj" -eq 4 ] && [ "$min" -ge 19 ]; then ok=1; fi
  if [ "$ok" -eq 1 ]; then
    row "OCP minimum (4.19+)" "✓ OK"
    if [ "$maj" -eq 4 ] && [ "$min" -lt 20 ]; then
      row "llm-d / Distributed Inference" "⚠ NOTE  (OCP 4.20+ required for llm-d)"
    fi
  else
    row "OCP minimum (4.19+)" "✗ FAIL  (have $ver; need 4.19+)"
    fail
  fi
else
  row "OCP minimum (4.19+)" "? UNKNOWN  (could not read ClusterVersion)"
  fail
fi

echo ""
echo "WORKER CAPACITY"
echo "$HR"

total_nodes=$(oc get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
workers=$(oc get nodes -l node-role.kubernetes.io/worker --no-headers 2>/dev/null | wc -l | tr -d ' ')
row "Total nodes" "$total_nodes"
row "Worker nodes (labeled)" "$workers"

if [ "${workers:-0}" -lt 1 ]; then
  row "Worker sizing" "✗ FAIL  (no nodes with node-role.kubernetes.io/worker)"
  fail
elif [ "${total_nodes:-0}" -eq 1 ] && [ "${workers:-0}" -ge 1 ]; then
  # Single-node OpenShift
  n=$(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[0].metadata.name}')
  cpu=$(oc get node "$n" -o jsonpath='{.status.allocatable.cpu}' 2>/dev/null)
  mem=$(oc get node "$n" -o jsonpath='{.status.allocatable.memory}' 2>/dev/null)
  cm=$(cpu_to_millicores "$cpu")
  ki=$(mem_to_ki "$mem")
  row "Mode" "SNO (single worker-capable node)"
  # 32 CPU = 32000m; 128 GiB ≈ 128 * 1024 * 1024 Ki (use 120 GiB floor in Ki)
  min_cpu_m=32000
  min_ki=$((120 * 1024 * 1024))
  if [ "${cm:-0}" -ge "$min_cpu_m" ] && [ "${ki:-0}" -ge "$min_ki" ]; then
    row "SNO allocatable (≥32 CPU, ≥120 GiB)" "✓ OK  (cpu=${cpu}, mem=${mem})"
  else
    row "SNO allocatable (≥32 CPU, ≥120 GiB)" "✗ FAIL  (cpu=${cpu}, mem=${mem})"
    fail
  fi
else
  if [ "${workers:-0}" -lt 2 ]; then
    row "Multi-node workers (need 2+)" "✗ FAIL  (only $workers worker(s))"
    fail
  else
    row "Multi-node workers (need 2+)" "✓ OK"
  fi
  bad=0
  while IFS= read -r n; do
    [ -z "$n" ] && continue
    cpu=$(oc get node "$n" -o jsonpath='{.status.allocatable.cpu}' 2>/dev/null)
    mem=$(oc get node "$n" -o jsonpath='{.status.allocatable.memory}' 2>/dev/null)
    cm=$(cpu_to_millicores "$cpu")
    ki=$(mem_to_ki "$mem")
    # ≥8 CPU (8000m); ≥30 GiB allocatable (nominal 32 Gi with system reserve)
    if [ "${cm:-0}" -lt 8000 ] || [ "${ki:-0}" -lt $((30 * 1024 * 1024)) ]; then
      row "  worker $n" "✗ FAIL  (need ≥8 CPU, ≥30 GiB alloc; have cpu=$cpu mem=$mem)"
      bad=1
    else
      row "  worker $n" "✓ OK  (cpu=$cpu mem=$mem)"
    fi
  done < <(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
  if [ "$bad" -ne 0 ]; then fail; fi
fi

echo ""
echo "STORAGE & AUTH"
echo "$HR"

defsc=""
while IFS= read -r sc; do
  [ -z "$sc" ] && continue
  if oc get storageclass "$sc" -o yaml 2>/dev/null \
     | grep -qE 'storageclass\.kubernetes\.io/is-default-class:\s*"?true"?'; then
    defsc=$sc
    break
  fi
done < <(oc get storageclass -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)

if [ -n "$defsc" ]; then
  row "Default StorageClass" "✓ OK  ($defsc)"
else
  row "Default StorageClass" "✗ FAIL  (no StorageClass marked default)"
  fail
fi

names=$(oc get oauth cluster -o jsonpath='{range .spec.identityProviders[*]}{.name}{" "}{end}' 2>/dev/null || true)
if [ -n "$names" ]; then
  row "Identity providers" "✓ OK  ($names)"
else
  row "Identity providers" "✗ FAIL  (no spec.identityProviders — configure OAuth IdP)"
  fail
fi

echo ""
echo "REQUIRED DEPENDENCY PRE-INSTALL STATUS"
echo "$HR"
echo "  Operators already installed are safe but require care:"
echo "  skip their 'oc apply -f 01-required-dependencies/<dir>/' block to"
echo "  avoid creating a duplicate OperatorGroup (TooManyOperatorGroups)."
echo ""

# ── check_dep_preinstall ──────────────────────────────────────────────────────
# Reports whether a required dependency is already installed.
# Warns on OperatorGroup conflicts in the target namespace.
check_dep_preinstall() {
  local label="$1" pattern="$2" ns="$3"
  local line sub_ns sub_name csv phase og_count og_names

  line=$(oc get subscription -A --no-headers 2>/dev/null | grep -iE "$pattern" | head -1)
  if [ -z "$line" ]; then
    row "$label" "— not installed  (safe to apply)"
    return
  fi

  sub_ns=$(echo  "$line" | awk '{print $1}')
  sub_name=$(echo "$line" | awk '{print $2}')
  csv=$(oc get subscription "$sub_name" -n "$sub_ns" \
        -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)
  phase=$(oc get csv "$csv" -n "$sub_ns" \
          -o jsonpath='{.status.phase}' 2>/dev/null || true)

  if [ "$phase" = "Succeeded" ]; then
    row "$label" "⚠ ALREADY INSTALLED  (csv: $csv) — skip oc apply or apply selectively"
  elif [ -n "$phase" ]; then
    row "$label" "⚠ PARTIAL INSTALL  (csv: $csv, phase: $phase) — review before applying"
    warn
  else
    row "$label" "⚠ SUBSCRIPTION EXISTS  (no installedCSV yet, ns: $sub_ns)"
    warn
  fi

  # Detect OperatorGroup conflicts in the target namespace
  og_count=$(oc get operatorgroup -n "$ns" --no-headers 2>/dev/null | grep -c . || true)
  if [ "${og_count:-0}" -gt 1 ]; then
    og_names=$(oc get operatorgroup -n "$ns" --no-headers 2>/dev/null \
               | awk '{print $1}' | tr '\n' ' ')
    row "  ↳ OperatorGroup conflict" "✗ FAIL  ($og_count OGs in ns/$ns: ${og_names% })"
    row "    Fix" "oc delete operatorgroup <duplicate> -n $ns"
    fail
  fi
}

check_dep_preinstall "cert-manager Operator"              "cert-manager"                      "cert-manager-operator"
check_dep_preinstall "Job Set Operator"                   "job-set|jobset"                    "openshift-jobset-operator"
check_dep_preinstall "Custom Metrics Autoscaler (KEDA)"   "custom-metrics-autoscaler"         "openshift-keda"
check_dep_preinstall "Red Hat build of OpenTelemetry"     "opentelemetry-product"             "openshift-opentelemetry-operator"
check_dep_preinstall "Tempo Operator"                     "tempo-product"                     "openshift-tempo-operator"
check_dep_preinstall "Cluster Observability Operator"     "cluster-observability-operator"    "openshift-cluster-observability-operator"

echo ""
echo "OPEN DATA HUB"
echo "$HR"

if oc get subscription -A --no-headers 2>/dev/null | grep -qiE 'opendatahub|odh-hub'; then
  row "ODH subscription absent" "✗ FAIL  (Open Data Hub subscription found — must not coexist with RHOAI install plan)"
  fail
else
  row "ODH subscription absent" "✓ OK"
fi

echo ""
echo "NETWORK (from cluster nodes)"
echo "$HR"
# Failures here are warnings only — registries may require a proxy in some environments.

NODE=$(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -z "$NODE" ]; then
  row "Registry / CDN reachability" "⚠ WARN  (no worker node found for oc debug)"
  warn
else
  row "Debug node (oc debug)" "$NODE"
  for pair in \
    "https://registry.redhat.io/v2/|registry.redhat.io/v2/" \
    "https://quay.io/v2/|quay.io/v2/" \
    "https://cdn.redhat.com|cdn.redhat.com"; do
    url="${pair%%|*}"
    label="${pair##*|}"
    code=$(http_code_from_node "$NODE" "$url")
    case "$code" in
      DNS_FAIL|CONN_FAIL|CURL_ERROR)
        row "$label" "⚠ WARN  ($code — check firewall / proxy config)"
        warn ;;
      *)
        if echo "$code" | grep -qE '^[0-9]{3}$'; then
          row "$label" "✓ REACHABLE  (HTTP $code)"
        else
          row "$label" "⚠ WARN  ($code)"
          warn
        fi ;;
    esac
  done
fi

echo ""
echo "SUBSCRIPTION (manual)"
echo "$HR"
row "RHOAI Self-Managed entitlement" "ℹ VERIFY  (ensure valid subscription outside this script)"

echo ""
echo "$HR"
if [ "$FAILURES" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  echo "  Summary: ✓ All checks passed"
elif [ "$FAILURES" -eq 0 ]; then
  echo "  Summary: ✓ All hard checks passed — $WARNINGS warning(s) to review (see ⚠ above)"
else
  echo "  Summary: ✗ $FAILURES check(s) failed — fix items marked FAIL before Phase 1"
  if [ "$WARNINGS" -gt 0 ]; then
    echo "           ⚠ $WARNINGS warning(s) to review (see ⚠ above)"
  fi
fi
  echo "  ✓ / ✓ OK = passed  ·  ✗ FAIL = blocking  ·  ⚠ WARN/ALREADY INSTALLED = review  ·  ℹ VERIFY = manual"
echo "$HR"
echo ""

exit "$FAILURES"
