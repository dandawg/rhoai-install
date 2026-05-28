#!/usr/bin/env bash
# RHOAI 3.4 — Phase 1 Dependency Check
# Checks that prerequisite operators are installed and instances are created.
# Run as a cluster-admin: bash guides/rhoai-dependency-check.sh

HR="────────────────────────────────────────────────────────────────────"

op_row()   { printf "  %-52s %s\n"   "$1" "$2"; }
inst_row() { printf "      %-48s %s\n" "$1" "$2"; }

FAILURES=0
WARNINGS=0
fail() { FAILURES=$((FAILURES + 1)); }
warn() { WARNINGS=$((WARNINGS + 1)); }

# ── check_op ─────────────────────────────────────────────────────────────────
# Looks up an OLM Subscription (not csv -A, which copies to every namespace).
# Pattern matched against the full line: NAMESPACE  SUB_NAME  PACKAGE  STATE
check_op() {
  local label="$1" pattern="$2"
  local line ns sub csv phase

  line=$(oc get subscription -A --no-headers 2>/dev/null | grep -iE "$pattern" | head -1)
  if [ -z "$line" ]; then
    op_row "$label" "— NOT INSTALLED"
    return
  fi

  ns=$(echo  "$line" | awk '{print $1}')
  sub=$(echo "$line" | awk '{print $2}')

  csv=$(oc get subscription "$sub" -n "$ns" \
        -o jsonpath='{.status.installedCSV}' 2>/dev/null)
  if [ -z "$csv" ]; then
    op_row "$label" "✗ PENDING  (subscription found; CSV not yet installed)  ns: $ns"
    fail
    return
  fi

  phase=$(oc get csv "$csv" -n "$ns" \
          -o jsonpath='{.status.phase}' 2>/dev/null)
  if [ "$phase" = "Succeeded" ]; then
    op_row "$label" "✓ READY  (ns: $ns, csv: $csv)"
  else
    op_row "$label" "✗ NOT READY ($phase)  ns: $ns, csv: $csv"
    fail
  fi
}

# ── check_og_health ───────────────────────────────────────────────────────────
# Warns if a namespace has multiple OperatorGroups (TooManyOperatorGroups).
# OLM will fail the CSV; fix by deleting the duplicate OG, then bouncing the sub.
check_og_health() {
  local namespace="$1"
  local count og_names reason
  count=$(oc get operatorgroup -n "$namespace" --no-headers 2>/dev/null | grep -c . || true)
  [ "${count:-0}" -le 1 ] && return
  og_names=$(oc get operatorgroup -n "$namespace" --no-headers 2>/dev/null \
             | awk '{print $1}' | tr '\n' ' ')
  inst_row "OperatorGroup conflict" \
    "✗ CONFLICT  ($count OGs in ns/$namespace: ${og_names% })"
  inst_row "  Fix" \
    "oc delete operatorgroup <duplicate> -n $namespace  (then bounce subscription)"
  fail
}

# ── check_pods ───────────────────────────────────────────────────────────────
# Count Running pods in an exact namespace; optional grep filter on pod name.
check_pods() {
  local label="$1" namespace="$2" filter="${3:-}"
  local count
  if [ -n "$filter" ]; then
    count=$(oc get pods -n "$namespace" --no-headers 2>/dev/null \
            | grep -E "$filter" | grep -c "Running" || true)
  else
    count=$(oc get pods -n "$namespace" --no-headers 2>/dev/null \
            | grep -c "Running" || true)
  fi
  if [ "${count:-0}" -gt 0 ]; then
    inst_row "$label" "✓ READY ($count pod(s) Running)"
  else
    inst_row "$label" "✗ NOT READY  (run: oc get pods -n $namespace)"
  fi
}

# ── check_cr ─────────────────────────────────────────────────────────────────
# Count CR instances cluster-wide.
check_cr() {
  local label="$1" kind="$2" optional="${3:-}"
  local count
  count=$(oc get "$kind" -A --no-headers 2>/dev/null | grep -c . || true)
  if [ "${count:-0}" -gt 0 ]; then
    inst_row "$label" "✓ READY ($count instance(s) found)"
  elif [ "$optional" = "optional" ]; then
    inst_row "$label" "— NOT CREATED  (optional / skip if not needed)"
  else
    inst_row "$label" "✗ NO INSTANCE  (create after operator install)"
  fi
}

# ── main ─────────────────────────────────────────────────────────────────────

echo ""
echo "$HR"
echo "  RHOAI 3.4 — Phase 1 Dependency Check"
echo "  $(date)"
echo "$HR"

# ─── REQUIRED ────────────────────────────────────────────────────────────────
# Per the official RHOAI 3.4 install guide, these are required dependencies
# for RHOAI 3.x. Install all of them before installing the RHOAI operator.
echo ""
echo "REQUIRED  (required dependencies per official RHOAI 3.4 install guide)"
echo "$HR"

# Package: cert-manager-operator  ns: cert-manager-operator
check_op        "cert-manager Operator"     "cert-manager"
check_og_health "cert-manager-operator"
check_pods      "  cert-manager pods"       "cert-manager"

# Package: job-set  ns: openshift-jobset-operator
# RHOAI may install this via OLM subscription OR deploy it directly.
# Check subscription first; fall back to pod/CRD check.
# NOTE: After operator install, a JobSetOperator CR (name: cluster) must be created manually.
_jobset_line=$(oc get subscription -A --no-headers 2>/dev/null \
               | grep -iE "job-set|jobset" | head -1)
if [ -n "$_jobset_line" ]; then
  _ns=$(echo "$_jobset_line"  | awk '{print $1}')
  _sub=$(echo "$_jobset_line" | awk '{print $2}')
  _csv=$(oc get subscription "$_sub" -n "$_ns" \
         -o jsonpath='{.status.installedCSV}' 2>/dev/null)
  _phase=$(oc get csv "$_csv" -n "$_ns" \
           -o jsonpath='{.status.phase}' 2>/dev/null)
  if [ "$_phase" = "Succeeded" ]; then
    op_row "Job Set Operator" "✓ READY  (ns: $_ns, csv: $_csv)"
  else
    op_row "Job Set Operator" "✗ NOT READY ($_phase)  ns: $_ns, csv: $_csv"
    fail
  fi
elif oc get pods -n openshift-jobset-operator --no-headers 2>/dev/null \
     | grep -q "Running"; then
  cnt=$(oc get pods -n openshift-jobset-operator --no-headers 2>/dev/null \
        | grep -c "Running" || true)
  op_row "Job Set Operator" "✓ READY  (ns: openshift-jobset-operator, $cnt pod(s) Running)"
else
  op_row "Job Set Operator" "— NOT INSTALLED  (install from OperatorHub: job-set)"
fi
check_og_health "openshift-jobset-operator"
# A JobSetOperator CR (name: cluster) must be created after operator install.
# Ref: https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/ai_workloads/jobset-operator
check_cr   "  → JobSetOperator instance" "JobSetOperator"

# Package: openshift-custom-metrics-autoscaler-operator  ns: openshift-keda
check_op        "Custom Metrics Autoscaler"       "custom-metrics-autoscaler"
check_og_health "openshift-keda"

# Package: opentelemetry-product (Red Hat build — NOT community opentelemetry-operator)
check_op        "Red Hat build of OpenTelemetry"  "opentelemetry-product"
check_og_health "openshift-opentelemetry-operator"

# Package: tempo-product (Red Hat build — NOT community tempo-operator)
check_op        "Tempo Operator"                  "tempo-product"
check_og_health "openshift-tempo-operator"

# Package: cluster-observability-operator
check_op        "Cluster Observability Operator"  "cluster-observability-operator"
check_og_health "openshift-cluster-observability-operator"

# ─── CONDITIONAL ─────────────────────────────────────────────────────────────
echo ""
echo "CONDITIONAL  (install only if applicable to your environment)"
echo "$HR"

echo ""
printf "  Node Feature Discovery (NFD)  [required if GPU nodes]\n"
# Package: nfd  ns: openshift-nfd
check_op   "  → Operator"                        "openshift-nfd"
check_cr   "  → NodeFeatureDiscovery instance"   "NodeFeatureDiscovery"

echo ""
printf "  NVIDIA GPU Operator  [required if using NVIDIA GPUs]\n"
# Package: gpu-operator-certified
check_op   "  → Operator"               "gpu-operator"
check_cr   "  → ClusterPolicy instance" "ClusterPolicy"

echo ""
printf "  AMD GPU Operator  [required if using AMD GPUs]\n"
check_op   "  → Operator"  "amd-gpu"

echo ""
printf "  Red Hat build of Kueue  [required if using distributed workloads]\n"
# Package: kueue-operator  ns: openshift-kueue-operator
# NOTE: After operator install, a Kueue CR (name: cluster) must be created manually.
# Ref: https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/ai_workloads/leader-worker-set-operator#kueue-creating-kueue-cr_kueue-operator
check_op   "  → Operator"                  "kueue-operator"
check_cr   "  → Kueue CR instance"         "Kueue"

echo ""
printf "  OpenShift Service Mesh 3.x  [required if using Llama Stack]\n"
# Package: servicemeshoperator3  (OSSM 3.x / Sail Operator)
check_op   "  → Operator"  "servicemeshoperator"

echo ""
printf "  Red Hat Leader Worker Set Operator  [required if using llm-d]\n"
# Package: leader-worker-set  ns: openshift-lws-operator
# NOTE: After operator install, a LeaderWorkerSetOperator CR instance must be created manually.
# Ref: https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/ai_workloads/leader-worker-set-operator#leader-worker-set-install_leader-worker-set-operator
check_op   "  → Operator"                          "leader-worker-set"
check_cr   "  → LeaderWorkerSetOperator instance"  "LeaderWorkerSetOperator"

echo ""
printf "  SR-IOV Network Operator  [required if using SR-IOV NICs / RDMA]\n"
check_op   "  → Operator"              "sriov-network-operator|sriov"
check_cr   "  → SriovOperatorConfig"  "SriovOperatorConfig" optional

echo ""
printf "  Red Hat Connectivity Link Operator  [required if using llm-d]\n"
# Package: rhcl-operator  ns: openshift-operators
check_op   "  → Operator"  "rhcl-operator|rhcl"

# ─── LEGEND ──────────────────────────────────────────────────────────────────
echo ""
echo "$HR"
echo "  ✓ READY         = Operator Subscription found, CSV Succeeded / CR instance found"
echo "  — NOT INSTALLED = No Subscription / CR found; OK if that feature is not in use"
echo "  ✗ NOT READY     = Installed but unhealthy — run: oc describe csv <name> -n <ns>"
echo "  ✗ NO INSTANCE   = Operator installed but required CR not yet created"
echo "  ✗ CONFLICT      = Multiple OperatorGroups in namespace — OLM will fail CSV"
echo "                    Fix: oc delete operatorgroup <duplicate> -n <ns>"
echo "                         then: oc delete csv <failed-csv> -n <ns>"
echo "                              oc delete subscription <sub> -n <ns> && oc apply -f ..."
echo "$HR"
if [ "$FAILURES" -eq 0 ]; then
  echo "  Summary: ✓ All checks passed — proceed to Phase 2"
else
  echo "  Summary: ✗ $FAILURES issue(s) found — resolve items marked ✗ before proceeding"
fi
echo "$HR"
echo ""

exit "$FAILURES"
