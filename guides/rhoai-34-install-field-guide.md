# RHOAI 3.4 — Installation Field Guide

Step-by-step field guide for installing **Red Hat OpenShift AI Self-Managed 3.4** on OpenShift 4.19+.
Use this alongside the [official install documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/installing_and_uninstalling_openshift_ai_self-managed).

**Companion scripts** (run from this repository root):

```bash
bash guides/rhoai-prerequisites-check.sh
```

```bash
bash guides/rhoai-dependency-check.sh
```

Scripts: [`guides/rhoai-prerequisites-check.sh`](rhoai-prerequisites-check.sh) (Phase 0 cluster checks), [`guides/rhoai-dependency-check.sh`](rhoai-dependency-check.sh) (Phase 1 operator checks).

**Last updated:** May 2026 · Based on the latest published Red Hat documentation

---

## Quick Reference

| Item | Value |
|---|---|
| Min OCP Version | 4.19 (4.20 required for llm-d Distributed Inference) |
| Operator Channel | `fast-3.x` (or `fast`, `stable`, `stable-x.y`) |
| Operator Namespace | `redhat-ods-operator` |
| Apps Namespace | `redhat-ods-applications` |
| Default Workbench Namespace | `rhods-notebooks` |
| Phase 0 prerequisite checks | `bash guides/rhoai-prerequisites-check.sh` ([`rhoai-prerequisites-check.sh`](rhoai-prerequisites-check.sh)) |
| Phase 1 dependency checks | `bash guides/rhoai-dependency-check.sh` ([`rhoai-dependency-check.sh`](rhoai-dependency-check.sh)) |

> **Upgrade note:** Upgrades from RHOAI 2.x → 3.x are not directly supported. 3.x is a new install only.
> See the [Upgrade KB article](https://access.redhat.com/articles/7133758).
> Do NOT install more than one RHOAI instance per cluster, and do NOT install alongside the RHOAI Add-on.

---

<details>
<summary><strong>Phase 0: Cluster Pre-Validation</strong></summary>

Run these checks before proceeding. All must pass. Log in as a non-`kubeadmin` cluster-admin user.

**Fast path** — from the repo root:

```bash
bash guides/rhoai-prerequisites-check.sh
```

See **Phase 0 Prerequisites Check Script** below for details. Use the manual commands for troubleshooting or extra context.

<details>
<summary>Pre-validation Commands (manual)</summary>

```bash
# Verify OCP version (must be 4.19–4.20)
oc version

# List nodes — need 2+ workers with 8 CPU + 32 GiB RAM (SNO: 32 CPU + 128 GiB)
oc get nodes -o wide
oc describe nodes | grep -A3 "Capacity:"

# Confirm a default StorageClass with dynamic provisioning exists
oc get storageclass

# Confirm an identity provider is configured (not just kubeadmin)
oc get oauth cluster -o jsonpath='{.spec.identityProviders}' | python3 -m json.tool

# Confirm Open Data Hub is NOT installed (must be absent)
oc get subscription -A | grep -i opendatahub || echo "ODH not found — OK"

# Test network access FROM A CLUSTER NODE (not your laptop).
# Image pulls happen on the nodes — your laptop having access is not sufficient.

# Step 1: Pick a worker node name
NODE=$(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[0].metadata.name}')
echo "Testing on node: $NODE"

# Step 2: Run curl from inside a debug pod on that node.
# These are container registries — they return 401 (Unauthorized) for unauthenticated requests.
# 401 = registry IS reachable and responded. curl error (exit 6/7) = NOT reachable.
oc debug node/$NODE -- chroot /host curl -s -o /dev/null -w "%{http_code}\n" https://registry.redhat.io/v2/
oc debug node/$NODE -- chroot /host curl -s -o /dev/null -w "%{http_code}\n" https://quay.io/v2/
oc debug node/$NODE -- chroot /host curl -s -o /dev/null -w "%{http_code}\n" https://cdn.redhat.com
# Expected: any HTTP status (200, 301, 401, 403) = REACHABLE
# Bad: "curl: (6) Could not resolve host" or "curl: (7) Failed to connect" = NOT reachable
```

</details>

### Phase 0 Prerequisites Check Script

```bash
bash guides/rhoai-prerequisites-check.sh
```

Run anytime after `oc login`. Checks cluster version, workers, default StorageClass, OAuth IdPs, ODH absence, and registry/CDN reachability from a worker node (via `oc debug`). Network check failures are reported as `⚠ WARN` (non-blocking) since registries may require a proxy in some environments.

The script exits `0` when all hard checks pass, or non-zero if any `✗ FAIL` items remain. RHOAI subscription and component-specific prerequisites (see below) are manual checks outside the script.

> **Reading the output:** `✓ OK` = passed · `✗ FAIL` = blocking · `⚠ WARN` = non-blocking, review · `ℹ VERIFY` = manual check needed

### Pre-Validation Checklist

| Check | Pass Criteria | Required |
|---|---|---|
| OCP version | 4.19 or 4.20 (4.20 for llm-d Distributed Inference) | **Required** |
| Worker nodes | 2+ nodes × 8 CPU + 32 GiB RAM (SNO: 32 CPU + 128 GiB) | **Required** |
| Default StorageClass | Marked `(default)`, dynamic provisioning enabled | **Required** |
| Identity Provider | At least one IdP configured (htpasswd, LDAP, OIDC, etc.) | **Required** |
| cluster-admin user | Non-`kubeadmin` user with `cluster-admin` role | **Required** |
| Open Data Hub | NOT installed on the cluster | **Required** |
| Network access (from nodes) | `registry.redhat.io/v2/`, `quay.io/v2/`, `cdn.redhat.com` return any HTTP code | **Required** |
| RHOAI subscription | Valid Red Hat OpenShift AI Self-Managed subscription | **Required** |

### Optional prerequisites (by component)

Plan these before enabling the matching DataScienceCluster components — they are not required to install RHOAI:

| If you enable… | Also need… |
|---|---|
| `aipipelines` | S3-compatible object storage |
| `modelregistry` | MySQL 5.x+ (8.x recommended) and S3 |
| `mlflowoperator` (production) | External DB and S3 |
| GPU / llm-d workloads | GPU nodes and optional dependency operators (NFD, GPU operator, LWS, etc.) |
| `llamastackoperator` | Service Mesh 3.x, cert-manager, GPU, NFD. **PostgreSQL required** for manually-created `LlamaStackDistribution` CRs (RAG/agentic use cases). The AI Playground auto-creates its own distribution (`lsd-genai-playground`). |

Model serving (`kserve`) does not require object storage — models can use PVC, OCI, S3, or inline sources.

</details>

---

<details>
<summary><strong>Phase 1: Prerequisite Operators</strong></summary>

Install the required operators (all 6) and any conditional operators that apply to your workloads before installing RHOAI. OperatorHub creates operator namespaces automatically.

> Some operators require creating a CR instance after install — these are clearly marked below with **Create CR** steps. Missing this step leaves the operator non-functional even though the subscription shows as `Succeeded`.

After completing all installs and CR creation steps, run the dependency check script from the repo root to validate everything before proceeding:

```bash
bash guides/rhoai-dependency-check.sh
```

### Required Operators

Install **all six** of these before installing the RHOAI operator. They are required for every RHOAI 3.x deployment per the [official install guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/installing_and_uninstalling_openshift_ai_self-managed).

| # | Operator | OperatorHub package | Namespace | CR required? |
|---|---|---|---|---|
| 1 | cert-manager | `cert-manager-operator` | `cert-manager-operator` | No |
| 2 | Job Set | `job-set` | `openshift-jobset-operator` | **Yes** — `JobSetOperator` |
| 3 | Custom Metrics Autoscaler (KEDA) | `openshift-custom-metrics-autoscaler-operator` | `openshift-keda` | No (auto-created) |
| 4 | Red Hat build of OpenTelemetry | `opentelemetry-product` | `openshift-opentelemetry-operator` | No |
| 5 | Tempo Operator | `tempo-product` | `openshift-tempo-operator` | No |
| 6 | Cluster Observability Operator | `cluster-observability-operator` | `openshift-cluster-observability-operator` | No |

---

#### 1. cert-manager Operator

| | |
|---|---|
| OperatorHub package | `cert-manager-operator` |
| Installed namespace | `cert-manager-operator` |
| CR instance required? | No — pods start automatically after install |

**Install:** Operators → OperatorHub → search `cert-manager-operator` → Install (All namespaces)

```bash
# Verify
oc get pods -n cert-manager
# Expected: 3 pods Running (cert-manager, cainjector, webhook)
```

---

#### 2. Job Set Operator

| | |
|---|---|
| OperatorHub package | `job-set` |
| Installed namespace | `openshift-jobset-operator` |
| CR instance required? | **Yes** — must create `JobSetOperator` CR after install |

**Install:** Operators → OperatorHub → search `job-set` → Install (All namespaces)

**Create CR** (the operator does not start until this is done — required for Kubeflow Trainer v2 distributed training):

```bash
cat <<EOF | oc apply -f -
apiVersion: jobset.x-k8s.io/v1alpha2
kind: JobSetOperator
metadata:
  name: cluster
spec:
  managementState: Managed
EOF
```

**Verify:**

```bash
oc get JobSetOperator cluster              # expect: managementState: Managed
oc get pods -n openshift-jobset-operator  # expect: jobset-operator pod Running
```

Ref: [OCP 4.21 — Job Set Operator](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/ai_workloads/jobset-operator#creating-jobset-operator-instance_jobset-operator)

---

#### 3. Custom Metrics Autoscaler (KEDA)

| | |
|---|---|
| OperatorHub package | `openshift-custom-metrics-autoscaler-operator` |
| Installed namespace | `openshift-keda` |
| CR instance required? | No — `KedaController` CR is created automatically (v2.17.2+) |

**Install:** Operators → OperatorHub → search `Custom Metrics Autoscaler` → Install (All namespaces)

```bash
# Verify
oc get pods -n openshift-keda
oc get KedaController -n openshift-keda  # expect: 1 resource (auto-created)
```

---

#### 4. Red Hat build of OpenTelemetry

| | |
|---|---|
| OperatorHub package | `opentelemetry-product` |
| Installed namespace | `openshift-opentelemetry-operator` |
| CR instance required? | No — RHOAI creates collector instances automatically via DSCI when observability is enabled |

**Install:** Operators → OperatorHub → search `Red Hat build of OpenTelemetry` → Install (All namespaces)

```bash
# Verify
oc get pods -n openshift-opentelemetry-operator
```

---

#### 5. Tempo Operator

| | |
|---|---|
| OperatorHub package | `tempo-product` |
| Installed namespace | `openshift-tempo-operator` |
| CR instance required? | No — RHOAI creates Tempo instances automatically via DSCI when observability is enabled |

**Install:** Operators → OperatorHub → search `Tempo Operator` → Install (All namespaces)

```bash
# Verify
oc get pods -n openshift-tempo-operator
```

---

#### 6. Cluster Observability Operator

| | |
|---|---|
| OperatorHub package | `cluster-observability-operator` |
| Installed namespace | `openshift-cluster-observability-operator` |
| CR instance required? | No — RHOAI manages observability resources via DSCI |

**Install:** Operators → OperatorHub → search `Cluster Observability Operator` → Install (All namespaces)

```bash
# Verify
oc get pods -n openshift-cluster-observability-operator
```

---

### Conditional Operators

Install only those relevant to your environment. Each entry is a complete Install → Configure → Verify sequence.

| Operator | OperatorHub package | Namespace | CR required? | When needed |
|---|---|---|---|---|
| NFD | `nfd` | `openshift-nfd` | **Yes** — `NodeFeatureDiscovery` | GPU nodes (install before GPU operators) |
| NVIDIA GPU Operator | `gpu-operator-certified` | `nvidia-gpu-operator` | **Yes** — `ClusterPolicy` | NVIDIA GPU nodes |
| AMD GPU Operator | `amd-gpu` | `openshift-amd-gpu` | No | AMD GPU nodes |
| Red Hat build of Kueue | `kueue-operator` | `openshift-kueue-operator` | **Yes** — `Kueue` (`cluster`) | Ray, TrainingOperator, batch workloads |
| OpenShift Service Mesh 3.x | `servicemeshoperator3` | `openshift-operators` | No (RHOAI creates CR) | Llama Stack / RAG |
| Leader Worker Set | `leader-worker-set` | `openshift-lws-operator` | **Yes** — `LeaderWorkerSetOperator` | llm-d Distributed Inference |
| SR-IOV Network Operator | `sriov-network-operator` | `openshift-sriov-network-operator` | No (auto-created) | SR-IOV / RDMA multi-node GPU |
| Red Hat Connectivity Link | `rhcl-operator` | `openshift-operators` | **Yes** — `Kuadrant` (`kuadrant-system`) in Post-Install | llm-d Distributed Inference |

---

#### NFD — Node Feature Discovery

**When needed:** Any cluster with GPU nodes (required before GPU operators).

| | |
|---|---|
| OperatorHub package | `nfd` |
| Installed namespace | `openshift-nfd` |
| CR instance required? | **Yes** — must create `NodeFeatureDiscovery` CR after install |

**Install:** Operators → OperatorHub → search `Node Feature Discovery` → Install (All namespaces)

**Create CR:**

```bash
# Via web console:
# Operators → Installed Operators → Node Feature Discovery → NodeFeatureDiscovery tab → Create NodeFeatureDiscovery

# Via CLI (minimal default instance):
cat <<EOF | oc apply -f -
apiVersion: nfd.openshift.io/v1
kind: NodeFeatureDiscovery
metadata:
  name: nfd-instance
  namespace: openshift-nfd
spec:
  operand:
    image: registry.redhat.io/openshift4/ose-node-feature-discovery-rhel9
    imagePullPolicy: Always
  workerConfig:
    configData: |
      core:
        sleepInterval: 60s
EOF
```

**Verify** (labels appear on nodes within ~2 minutes):

```bash
oc get NodeFeatureDiscovery -n openshift-nfd
NODE=$(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[0].metadata.name}')
oc describe node $NODE | grep "feature.node.kubernetes.io" | head -5
```

---

#### NVIDIA GPU Operator

**When needed:** Clusters with NVIDIA GPU nodes.

| | |
|---|---|
| OperatorHub package | `gpu-operator-certified` |
| Installed namespace | `nvidia-gpu-operator` |
| CR instance required? | **Yes** — must create `ClusterPolicy` CR after install |

**Prerequisite:** NFD must be installed and running first.

**Install:** Operators → OperatorHub → search `NVIDIA GPU Operator` → Install (All namespaces)

**Create CR:**

```bash
# Via web console (recommended — defaults are correct for most clusters):
# Operators → Installed Operators → NVIDIA GPU Operator → ClusterPolicy tab → Create ClusterPolicy → Create

# Via CLI (accept defaults):
cat <<EOF | oc apply -f -
apiVersion: nvidia.com/v1
kind: ClusterPolicy
metadata:
  name: gpu-cluster-policy
spec:
  operator:
    defaultRuntime: crio
EOF
```

**Verify** (GPU driver load takes ~5 minutes):

```bash
oc get ClusterPolicy gpu-cluster-policy
oc get pods -n nvidia-gpu-operator
oc describe node <gpu-node-name> | grep "nvidia.com/gpu"
# Expected: nvidia.com/gpu: <N>  in both Capacity and Allocatable sections
```

**Optional — Enable GPU Monitoring Dashboard:**

The GPU Operator exposes GPU telemetry via NVIDIA DCGM Exporter, which can be visualized in the OCP web console under **Observe → Dashboards**. To add the NVIDIA DCGM Exporter Dashboard:

```bash
# Download the dashboard definition
curl -LfO https://github.com/NVIDIA/dcgm-exporter/raw/main/grafana/dcgm-exporter-dashboard.json

# Create the ConfigMap and label it so the console picks it up
oc create configmap nvidia-dcgm-exporter-dashboard \
  -n openshift-config-managed \
  --from-file=dcgm-exporter-dashboard.json

oc label configmap nvidia-dcgm-exporter-dashboard \
  -n openshift-config-managed \
  "console.openshift.io/dashboard=true"
```

View at: **Observe → Dashboards → NVIDIA DCGM Exporter Dashboard** in the Administrator perspective.

See [Enabling the GPU Monitoring Dashboard](https://docs.nvidia.com/datacenter/cloud-native/openshift/latest/enable-gpu-monitoring-dashboard.html) for full details.

---

#### AMD GPU Operator

**When needed:** Clusters with AMD GPU nodes.

| | |
|---|---|
| OperatorHub package | `amd-gpu` |
| Installed namespace | `openshift-amd-gpu` |
| CR instance required? | No — operator manages itself |

**Install:** Operators → OperatorHub → search `AMD GPU Operator` → Install (All namespaces)

```bash
# Verify
oc get pods -n openshift-amd-gpu
oc describe node <gpu-node-name> | grep "amd.com/gpu"
```

---

#### Red Hat build of Kueue

**When needed:** Distributed workloads using Ray, Kubeflow TrainingOperator, or other batch frameworks.

| | |
|---|---|
| OperatorHub package | `kueue-operator` |
| Installed namespace | `openshift-kueue-operator` |
| CR instance required? | **Yes** — must create `Kueue` CR after install; name must be `cluster` |

**Install:** Operators → OperatorHub → search `Red Hat build of Kueue` → Install (All namespaces)

**Create CR:**

```bash
cat <<EOF | oc apply -f -
apiVersion: kueue.openshift.io/v1
kind: Kueue
metadata:
  name: cluster
  namespace: openshift-kueue-operator
spec:
  managementState: Managed
  config:
    integrations:
      frameworks:
        - BatchJob
EOF
```

> Add additional frameworks if needed: `RayJob`, `RayCluster`, `PyTorchJob`, `Pod`, `Deployment`, `StatefulSet`.

**Verify:**

```bash
oc get Kueue cluster -n openshift-kueue-operator
oc get pods -n openshift-kueue-operator | grep kueue-controller-manager
# Expected: kueue-controller-manager pod Running
```

Ref: [OCP 4.21 — Creating a Kueue CR](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/ai_workloads/leader-worker-set-operator#kueue-creating-kueue-cr_kueue-operator)

---

#### OpenShift Service Mesh 3.x

**When needed:** Llama Stack / RAG workloads.

| | |
|---|---|
| OperatorHub package | `servicemeshoperator3` |
| Installed namespace | `openshift-operators` (cluster-scoped) |
| CR instance required? | No — RHOAI creates the `ServiceMesh` CR automatically when Llama Stack is enabled in the DSC |

**Install:** Operators → OperatorHub → search `Red Hat OpenShift Service Mesh` (select the 3.x version) → Install (All namespaces)

```bash
# Verify operator is installed
oc get subscription -A | grep servicemeshoperator
```

---

#### Red Hat Leader Worker Set Operator

**When needed:** Distributed Inference with llm-d.

| | |
|---|---|
| OperatorHub package | `leader-worker-set` |
| Installed namespace | `openshift-lws-operator` |
| CR instance required? | **Yes** — must create `LeaderWorkerSetOperator` CR after install |

**Prerequisite:** cert-manager Operator must be installed first.

**Install:** Operators → OperatorHub → search `Leader Worker Set` → Install (All namespaces)

**Create CR:**

```bash
# Via web console:
# Operators → Installed Operators → Leader Worker Set Operator → LeaderWorkerSetOperator tab → Create instance

# Via CLI:
cat <<EOF | oc apply -f -
apiVersion: leaderworkerset.x-k8s.io/v1
kind: LeaderWorkerSetOperator
metadata:
  name: cluster
  namespace: openshift-lws-operator
spec:
  managementState: Managed
EOF
```

**Verify:**

```bash
oc get LeaderWorkerSetOperator cluster -n openshift-lws-operator
oc get pods -n openshift-lws-operator
```

Ref: [OCP 4.21 — Leader Worker Set Operator](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/ai_workloads/leader-worker-set-operator#leader-worker-set-install_leader-worker-set-operator)

---

#### SR-IOV Network Operator

**When needed:** Multi-node GPU training over InfiniBand/RoCE (RDMA), SR-IOV capable NICs.

| | |
|---|---|
| OperatorHub package | `sriov-network-operator` |
| Installed namespace | `openshift-sriov-network-operator` |
| CR instance required? | No — `SriovOperatorConfig` is created automatically |

**Install:** Operators → OperatorHub → search `SR-IOV Network Operator` → Install (All namespaces)

```bash
# Verify
oc get SriovOperatorConfig -n openshift-sriov-network-operator
oc get pods -n openshift-sriov-network-operator
```

---

#### Red Hat Connectivity Link Operator

**When needed:** Distributed Inference with llm-d. After installing, a `Kuadrant` CR must be created in `kuadrant-system` to activate the control plane — this is what provisions the Envoy Gateway controller that serves the llm-d GatewayClass. Configure the `GatewayClass` and `Gateway` **after** the Kuadrant CR is Ready (see Post-Install section).

> **Order matters:** Apply the Kuadrant CR first, wait for it to be Ready, then apply the GatewayClass and Gateway. Applying the GatewayClass before Kuadrant is running causes the controller to miss the resource and stay `Unknown`.

| | |
|---|---|
| OperatorHub package | `rhcl-operator` |
| Installed namespace | `openshift-operators` (cluster-scoped) |
| CR instance required? | **Yes** — `Kuadrant` in `kuadrant-system` (Post-Install, before GatewayClass) |

**Install:** Operators → OperatorHub → search `Red Hat Connectivity Link` → Install (All namespaces)

```bash
# Verify operator
oc get subscription -A | grep rhcl
```

Ref: [Deploying models with Distributed Inference (llm-d)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/deploy_models_using_distributed_inference_with_llm-d/deploying-models-using-distributed-inference_distributed-inference#enabling-distributed-inference_distributed-inference)


### Phase 1 Dependency Check Script

```bash
bash guides/rhoai-dependency-check.sh
```

Run after completing all Phase 1 installs to verify operators before installing RHOAI. The script checks each operator's CSV phase and its instances/pods, and outputs a table like:

```
────────────────────────────────────────────────────────────────────
  RHOAI 3.4 — Phase 1 Dependency Check
────────────────────────────────────────────────────────────────────

REQUIRED  (must be installed before RHOAI operator)
────────────────────────────────────────────────────────────────────
  cert-manager Operator                                ✓ READY  (ns: cert-manager-operator, csv: cert-manager-operator.v1.x.x)
        cert-manager pods                              ✓ READY (3 pod(s) Running)
  Job Set Operator                                     ✓ READY  (ns: openshift-jobset-operator, csv: jobset-operator.v1.0.0)
        → JobSetOperator instance                      ✓ READY (1 instance(s) found)
  Custom Metrics Autoscaler                            ✓ READY  (ns: openshift-keda, csv: custom-metrics-autoscaler.v2.x.x)
  Red Hat build of OpenTelemetry                       ✓ READY  (ns: openshift-opentelemetry-operator, csv: ...)
  Tempo Operator                                       ✓ READY  (ns: openshift-tempo-operator, csv: ...)
  Cluster Observability Operator                       ✓ READY  (ns: openshift-cluster-observability-operator, csv: ...)

CONDITIONAL  (install only if applicable to your environment)
────────────────────────────────────────────────────────────────────
  Node Feature Discovery (NFD)  [required if GPU nodes]
    → Operator                                       ✓ READY  (ns: openshift-nfd, csv: nfd.4.x.x)
        → NodeFeatureDiscovery instance              ✓ READY (1 instance(s) found)

  Red Hat build of Kueue  [required if using distributed workloads]
    → Operator                                       ✓ READY  (ns: openshift-kueue-operator, csv: kueue-operator.v1.x.x)
        → Kueue CR instance                          ✓ READY (1 instance(s) found)

  Red Hat Leader Worker Set  [required if using llm-d]
    → Operator                                       ✓ READY  (ns: openshift-lws-operator, csv: ...)
        → LeaderWorkerSetOperator instance           ✓ READY (1 instance(s) found)

  OpenShift Service Mesh 3.x  [required if using Llama Stack]
    → Operator                                       ✓ READY  (ns: openshift-operators, csv: servicemeshoperator3.v3.x.x)
```

> **Reading the output:**
> - `✓ READY` — operator subscription found and CSV Succeeded / CR instance found
> - `— NOT INSTALLED` — operator or CR not found; must be installed/created if required
> - `✗ NOT READY` — operator installed but unhealthy — run `oc describe csv <name> -n <ns>`
> - `✗ NO INSTANCE` — operator installed but required CR not yet created (see Phase 1 instructions above)

<details>
<summary>Troubleshooting: check CSV status for any operator</summary>

Use this pattern to check if a specific operator's subscription is healthy and its CSV has fully installed. Run `oc get subscription -A` first to find the subscription name and namespace.

```bash
# Check all subscriptions at once (look for AtLatestKnown or UpgradePending states)
oc get subscription -A

# Deep-check a specific operator's CSV status:
SUB=<sub-name>; NS=<namespace>
CSV=$(oc get subscription $SUB -n $NS -o jsonpath='{.status.installedCSV}')
oc get csv $CSV -n $NS -o jsonpath='{.status.phase}{"\n"}'   # expect: Succeeded
oc describe csv $CSV -n $NS | grep -A5 "Conditions:"

# Check all required operator subscriptions at once:
oc get subscription -A | grep -iE "cert-manager|job-set|custom-metrics-autoscaler|opentelemetry-product|tempo-product|cluster-observability"

# Check all CR instances that must exist:
oc get JobSetOperator -A
oc get NodeFeatureDiscovery -A
oc get ClusterPolicy -A
oc get Kueue -A
oc get LeaderWorkerSetOperator -A
```

</details>

</details>

---

<details>
<summary><strong>Phase 2: Install the RHOAI Operator</strong></summary>

Use either the CLI steps below or the OpenShift web console (**Operators → OperatorHub → "Red Hat OpenShift AI"**). If using the web console, skip Steps 2.1 through 2.3 — OperatorHub creates the namespace and OperatorGroup automatically.

> **Channel:** Use `fast-3.x` for RHOAI 3.x. See [channel docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/installing_and_uninstalling_openshift_ai_self-managed/understanding-update-channels_install).

### Step 2.1 — Create the Operator Namespace *(CLI only)*

```bash
cat <<EOF | oc create -f -
apiVersion: v1
kind: Namespace
metadata:
  name: redhat-ods-operator
EOF

oc get namespace redhat-ods-operator
```

### Step 2.2 — Create an OperatorGroup *(CLI only)*

```bash
cat <<EOF | oc create -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
EOF
```

### Step 2.3 — Create the Subscription

```bash
cat <<EOF | oc create -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
spec:
  name: rhods-operator
  channel: fast-3.x        # or: fast, stable, stable-x.y, eus-x.y
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

### Step 2.4 — Verify Operator Installed Successfully

```bash
# Watch the operator installation (wait for Succeeded)
oc get csv -n redhat-ods-operator -w

# Or check in the console:
# Operators → Installed Operators → confirm "Red Hat OpenShift AI" shows Succeeded
```

[Operator install docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/installing_and_uninstalling_openshift_ai_self-managed/installing-and-deploying-openshift-ai_install#installing-the-openshift-ai-operator_operator-install)

</details>

---

<details>
<summary><strong>Phase 3: Configure the DataScienceCluster (Install Components)</strong></summary>

Create a `DataScienceCluster` CR to enable RHOAI components.
Set each component's `managementState` to `Managed` (install) or `Removed` (do not install).

### Component Reference

| Component | When Needed | Purpose | External Prerequisites |
|---|---|---|---|
| `dashboard` | Always | RHOAI web UI | None |
| `workbenches` | Core | JupyterLab, VS Code, RStudio notebooks | None (default StorageClass recommended) |
| `aipipelines` | Core | Kubeflow Pipelines / AI workflow automation | S3-compatible object storage |
| `kserve` | Core | Single-model serving platform (LLMs, vLLM, KServe) | cert-manager |
| `kueue` | If using distributed workloads | Job queuing for distributed workloads | Red Hat build of Kueue Operator |
| `ray` | If using distributed workloads | Ray distributed compute for model training/fine-tuning | Kueue Operator + cert-manager |
| `trainingoperator` | If using distributed training | Kubeflow Training Operator for distributed training jobs | Kueue Operator + cert-manager |
| `modelregistry` | Optional | Centralized model metadata registry | MySQL 5.x+ (8.x recommended) + S3 |
| `trustyai` | Optional | AI model monitoring, explainability, and bias detection | None |
| `llamastackoperator` | Optional — RAG/GenAI | Llama Stack for RAG and GenAI applications; AI Playground auto-creates its distribution (`lsd-genai-playground`); manually-created distributions (for RAG/SDK use) require PostgreSQL | Service Mesh 3.x + cert-manager + GPU + NFD |
| `feastoperator` | Optional — Feature Store | Feast Feature Store for ML feature management | None |
| `kubeflowsparkoperator` | Optional — Spark data processing | Kubeflow Spark Operator (Apache Spark 4.x) | None (needs a custom Spark image) |
| `mlflowoperator` | Optional — Experiment tracking | MLflow with Kubernetes RBAC | PVC (dev) or external DB + S3 (prod) |

### Create the DataScienceCluster CR

**GUI:** Operators → Installed Operators → Red Hat OpenShift AI → Data Science Cluster tab → Create DataScienceCluster → switch to YAML view → paste the YAML below (customized for your environment) → Create

**CLI:** Customize `managementState` values for your environment, then apply:

```bash
cat <<EOF | oc create -f -
apiVersion: datasciencecluster.opendatahub.io/v2
kind: DataScienceCluster
metadata:
  name: default-dsc
spec:
  components:
    dashboard:
      managementState: Managed           # Always enable
    workbenches:
      managementState: Managed           # Required for data science notebooks
      workbenchNamespace: rhods-notebooks
    aipipelines:
      managementState: Managed           # Enable for AI pipeline workflows
      argoWorkflowsControllers:
        managementState: Managed         # Set to Removed if using your own Argo instance
    kserve:
      managementState: Managed           # Enable for single-model serving (requires cert-manager)
    kueue:
      managementState: Unmanaged         # Use Unmanaged when Kueue Operator is installed
      defaultClusterQueueName: default
      defaultLocalQueueName: default
    ray:
      managementState: Managed           # Enable for Ray-based distributed workloads
    trainingoperator:
      managementState: Managed           # Enable for Kubeflow Training Operator jobs
    modelregistry:
      managementState: Managed           # Enable for model metadata registry
      registriesNamespace: rhoai-model-registries
    trustyai:
      managementState: Managed           # Enable for model monitoring/explainability
    llamastackoperator:
      managementState: Removed           # Set to Managed only for Llama Stack/RAG use cases
    feastoperator:
      managementState: Removed           # Set to Managed only for Feature Store use cases
    kubeflowsparkoperator:
      managementState: Removed           # Set to Managed for Apache Spark distributed data processing
    mlflowoperator:
      managementState: Removed           # Set to Managed for MLflow experiment tracking
EOF
```

### Component Validation

```bash
# Watch components become ready (may take 5-10 minutes)
oc get datasciencecluster default-dsc

# Verify DataScienceCluster is Ready
oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}'
# Expected: Ready

# Verify installed component pods
oc get pods -n redhat-ods-applications
```

| Check | Command / Action | Expected |
|---|---|---|
| DataScienceCluster phase | `oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}'` | `Ready` |
| Component pods running | `oc get pods -n redhat-ods-applications` | All pods Running or Completed |
| Installed components list | RHOAI Dashboard → Help icon → About | Shows installed components and versions |
| DSC status.installedComponents | YAML tab of `default-dsc` → `status.installedComponents` | Enabled components show `true` |

[Component install docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/installing_and_uninstalling_openshift_ai_self-managed/installing-and-deploying-openshift-ai_install#installing-and-managing-openshift-ai-components_component-install)

</details>

---

<details>
<summary><strong>Phase 4: Configure User Access</strong></summary>

By default, all OpenShift users can access RHOAI. Optionally restrict access using user groups.
Users in the `cluster-admin` group automatically have RHOAI admin access.

> **Optional** — Skip to allow all OpenShift users to access RHOAI.

```bash
# Option A: Use existing IdP groups
# RHOAI Dashboard → Settings → User management → specify group names

# Option B: Create groups and add users via CLI
oc adm groups new rhods-users
oc adm groups add-users rhods-users <username1> <username2>

oc adm groups new rhods-admins
oc adm groups add-users rhods-admins <admin-username>

# Then configure RHOAI to use these groups:
# RHOAI Dashboard → Settings → User management
# Set "Data scientists" group = rhods-users
# Set "Administrators" group = rhods-admins
```

> If using LDAP: configure LDAP sync first. See [LDAP syncing docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/authentication_and_authorization/ldap-syncing).

[User management docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/managing_openshift_ai/managing-users-and-groups#adding-users-to-user-groups_managing-rhoai)

</details>

---

<details>
<summary><strong>Phase 5: Access Dashboard &amp; Final Validation</strong></summary>

```bash
# Get the dashboard URL (RHOAI 3.4+)
echo "https://rh-ai.$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}')"

# Or from the OpenShift web console:
# Click the application launcher (grid icon, top right) → Red Hat OpenShift AI
```

> **Note:** Starting with RHOAI 3.4, the dashboard is served via the Gateway API and the URL follows the format `https://rh-ai.apps.<cluster-domain>`. The command above reads the cluster's ingress domain directly to construct it. Running `oc get route -n redhat-ods-applications` will only show legacy redirect routes (`rhods-dashboard`, `data-science-gateway`) that redirect to this new URL — they are not the canonical endpoint.

### Final Validation Checklist

| Validation | Where / How | Expected |
|---|---|---|
| Dashboard loads | Open RHOAI dashboard URL in browser | Login page appears, login succeeds |
| Components visible | Dashboard → Help → About | All enabled components listed |
| Operator healthy | OCP console: Operators → Installed Operators → RHOAI → Data Science Cluster → `default-dsc` | Phase: Ready |
| Pods healthy | `oc get pods -n redhat-ods-applications` | No pods in CrashLoopBackOff or Error |
| GPU detected (if applicable) | `oc describe node <gpu-node> \| grep nvidia.com/gpu` | GPU shown in Capacity and Allocatable |
| Kueue running (if applicable) | `oc get pods -n openshift-kueue-operator` | `kueue-controller-manager` Running |
| User can log in | Log in as a data scientist user (non-admin) | Dashboard visible with projects |

</details>

---

<details>
<summary><strong>Post-Install: Component-Specific Configuration</strong></summary>

<details>
<summary><strong>Hardware Profiles</strong></summary>

Create hardware profiles so data scientists can select GPU resources when deploying models or running workbenches.

**GUI:** RHOAI Dashboard → Settings → Environment setup → Hardware profiles → Add hardware profile

[Hardware profiles docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_accelerators/working-with-hardware-profiles_accelerators)

</details>

<details>
<summary><strong>AI Pipelines: Configure Object Storage</strong></summary>

AI pipelines require S3-compatible object storage for artifacts, logs, and results.

**GUI:**
1. RHOAI Dashboard → Data Science Projects → \[project\] → Connections → Add connection → S3-compatible object storage
2. Then: Data Science Projects → \[project\] → Pipelines → Configure pipeline server

[AI Pipelines docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_ai_pipelines)

</details>

<details>
<summary><strong>Distributed Workloads (kueue + ray/trainingoperator): Configure Kueue Queues</strong></summary>

Create `ClusterQueue` and `LocalQueue` resources so data scientists can submit workloads.

```bash
cat <<EOF | oc apply -f -
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: default
spec:
  namespaceSelector: {}
  resourceGroups:
  - coveredResources: ["cpu", "memory", "nvidia.com/gpu"]
    flavors:
    - name: default
      resources:
      - name: cpu
        nominalQuota: "16"
      - name: memory
        nominalQuota: 64Gi
      - name: nvidia.com/gpu
        nominalQuota: "4"
EOF
```

[Distributed workloads management docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/managing_openshift_ai/managing-distributed-workloads_managing-rhoai)

</details>

<details>
<summary><strong>Model Registry: Create a Registry Instance</strong></summary>

Requires either MySQL 5.x+ (8.x recommended) or the built-in default database (not for production).

**GUI:** RHOAI Dashboard → Settings → Model registry → Create model registry

[Model Registry creation docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/managing_model_registries/creating-a-model-registry_managing-model-registries)

</details>

<details>
<summary><strong>Distributed Inference with llm-d: Configure Gateway (Optional)</strong></summary>

> **Requires:** kserve enabled, Leader Worker Set Operator, Connectivity Link Operator (RHCL), OCP 4.20+.
> **Note:** OpenShift Service Mesh v2 must NOT be installed — only v3 or none.

**Complete all four steps in order.** Steps 1–2 activate Kuadrant (which provisions the Envoy Gateway controller). Steps 3–4 create the gateway resources. Applying the GatewayClass before Kuadrant is Ready causes the controller to miss the event and remain `Unknown` indefinitely.

**Step 1 — Create the `kuadrant-system` namespace and Kuadrant CR**

```bash
# Namespace must exist before the CR
oc create namespace kuadrant-system --dry-run=client -o yaml | oc apply -f -

oc apply -f 05-configuration/llm-d/kuadrant-cr.yaml

# Wait for Kuadrant to be Ready (1-3 minutes)
oc wait Kuadrant kuadrant -n kuadrant-system --for=condition=Ready --timeout=10m

# Verify
oc get kuadrant kuadrant -n kuadrant-system \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
# Expected: True
```

**Step 2 — Configure Authorino TLS**

Required for auth policy enforcement on the llm-d gateway.

```bash
# Annotate the Authorino service to trigger OpenShift service-ca cert generation.
# Note: the service is named 'authorino-authorino-authorization' by Kuadrant.
oc annotate svc/authorino-authorino-authorization \
  -n kuadrant-system \
  service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert

# Wait briefly for the secret to be created
sleep 5

# Enable TLS on the Authorino listener (apply full spec per docs — patch may miss fields)
cat <<EOF | oc apply -f -
apiVersion: operator.authorino.kuadrant.io/v1beta1
kind: Authorino
metadata:
  name: authorino
  namespace: kuadrant-system
spec:
  replicas: 1
  clusterWide: true
  listener:
    tls:
      enabled: true
      certSecretRef:
        name: authorino-server-cert
  oidcServer:
    tls:
      enabled: false
EOF

# Wait for Authorino pods to be ready
oc wait --for=condition=ready pod -l authorino-resource=authorino \
  -n kuadrant-system --timeout=150s

# Verify
oc get secret authorino-server-cert -n kuadrant-system
oc get authorino authorino -n kuadrant-system \
  -o jsonpath='{.spec.listener.tls.enabled}'
# Expected: true
```

> **If RHOAI was installed before installing Connectivity Link:** restart the model serving controllers so they pick up the new auth infrastructure:
>
> ```bash
> oc delete pod -n redhat-ods-applications -l app=odh-model-controller
> oc delete pod -n redhat-ods-applications -l control-plane=kserve-controller-manager
> ```

**Step 3 — Create the GatewayClass (once per cluster)**

```bash
oc apply -f 05-configuration/llm-d/gateway-class.yaml

# Verify — should be Accepted: True (not Unknown)
oc get gatewayclass openshift-ai-inference
```

**Step 4 — Create the shared Gateway in `openshift-ingress`**

> **Prerequisite:** The RHOAI operator must have provisioned the `data-science-gateway-service-tls`
> Secret in `openshift-ingress` before this Gateway is applied. Verify:
> `oc get secret data-science-gateway-service-tls -n openshift-ingress`

```bash
oc apply -f 05-configuration/llm-d/gateway.yaml

# Verify — should be Programmed: True
oc get gateway openshift-ai-inference -n openshift-ingress
```

[Enabling Distributed Inference with llm-d](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/deploy_models_using_distributed_inference_with_llm-d/deploying-models-using-distributed-inference_distributed-inference#enabling-distributed-inference_distributed-inference) · [Configuring authentication for llm-d](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/deploy_models_using_distributed_inference_with_llm-d/configuring-authentication-for-llmd_distributed-inference)

</details>

<details>
<summary><strong>Llama Stack: AI Playground and RAG Workflows (Optional)</strong></summary>

The Llama Stack Operator manages `LlamaStackDistribution` CRs. There are **two distinct use cases** with different setup requirements:

---

#### Use Case A — AI Playground (auto-managed, no manual CR needed)

The gen-ai-studio AI Playground **auto-creates** a `LlamaStackDistribution` named **`lsd-genai-playground`** in the user's project when a playground instance is created. Admins do not create this CR manually — it is managed by the platform.

**Prerequisite flow (official docs):**

1. `genAiStudio: true` is set in `OdhDashboardConfig` ← cluster admin
2. `llamastackoperator: Managed` in `DataScienceCluster` ← cluster admin
3. Model is deployed as an **AI asset endpoint** — the InferenceService must have the label `opendatahub.io/genai-asset: "true"` ← set at deploy time (check "Add as AI asset endpoint" in the dashboard, or add the label to the InferenceService manifest)
4. User navigates to **Gen AI studio → AI asset endpoints**, finds their model, and clicks **Add to playground**
5. The platform creates `lsd-genai-playground` and the playground interface loads

> **Tech Preview known behavior:** Background gen-ai-ui logs will show `no LlamaStackDistribution found` errors while browsing playground pages before a playground instance is created. These are expected polling failures, not crashes.

> **Tech Preview known bug (RHOAI 3.4):** The "Gen AI studio → Playground → Create playground" path crashes with `Cannot read properties of null (reading 'find')` when no `lsd-genai-playground` exists yet. **Workaround:** Always create a playground via **"AI asset endpoints → Add to playground"** instead. This is also the path documented as the primary flow in the official prerequisites guide.
>
> **If the auto-created `lsd-genai-playground` is still not discovered by the gen-ai-ui:** Verify the LSD has the label `opendatahub.io/dashboard: "true"`. The gen-ai-ui informer uses this label as a selector — LSDs missing this label are invisible to the dashboard even if they are `Ready`. Check with `oc get lsd -n <project> --show-labels`. If missing, add it: `oc label lsd lsd-genai-playground -n <project> opendatahub.io/dashboard=true`

> **Model type requirement:** Only `generative` (chat/completions) models work in the playground. Embedding models (`opendatahub.io/model-type: embedding`) will not function as conversational endpoints. Ensure the model is also not stopped (`serving.kserve.io/stop: "true"` annotation must not be present).
>
> **Undocumented requirements (RHOAI 3.4 Tech Preview gap):** Even with the LSD running and labeled correctly, the Playground will crash with `"Error loading components / Cannot read properties of null (reading 'find')"` if:
> 1. `ENABLE_SENTENCE_TRANSFORMERS` is not set to `"true"` — the gen-ai-ui auto-creates a default vector store on load using model ID `sentence-transformers/ibm-granite/granite-embedding-125m-english`. The `rh-dev` distribution ships this model in its image cache but the provider is disabled by default.
> 2. `ENABLE_FAISS` (or another vector store backend) is not set to `"true"` — all vector_io backends are gated behind env vars and none are enabled by default.
> Neither of these requirements is documented in the official RHOAI 3.4 release notes or the Working with Llama Stack guide.

> **If `lsd-genai-playground` fails to start:** Check the pod logs — `oc logs -n <project> -l app.kubernetes.io/part-of=lsd-genai-playground`. If the pod errors on a missing PostgreSQL connection, see Use Case B below; the auto-created distribution may inherit the same PostgreSQL requirement as manually-created distributions.

**Reference:** [Playground prerequisites](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/experimenting_with_models_in_the_gen_ai_playground/playground-prerequisites_rhoai-user) · [Experimenting with models in the gen AI playground](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/experimenting_with_models_in_the_gen_ai_playground/index)

---

#### Use Case B — RAG / Agentic Applications (manual CR required)

For programmatic Llama Stack API access (RAG pipelines, agentic workflows built with the Llama Stack SDK), you create a `LlamaStackDistribution` CR manually. This is **separate from the playground** and is needed when data scientists build apps against the Llama Stack API directly.

> **PostgreSQL is required** for all vector store and metadata backends (inline FAISS, inline Milvus Lite, and pgvector all use PostgreSQL for metadata persistence). SQLite-based storage is no longer recommended in RHOAI 3.4. Provision PostgreSQL before creating the distribution.

**Step 1 — Enable the llamastackoperator in the DataScienceCluster**

```bash
oc patch datasciencecluster default-dsc \
  --type=merge \
  -p '{"spec":{"components":{"llamastackoperator":{"managementState":"Managed"}}}}'

# Verify
oc get pods -n redhat-ods-applications -l app=llama-stack-k8s-operator
```

**Step 2 — Create a PostgreSQL Secret in your data science project**

```bash
# Write password to a temp file (avoids shell history exposure)
echo -n 'your-pg-password' > /tmp/pg-password.txt

oc create secret generic llamastack-postgres-secret \
  --from-file=password=/tmp/pg-password.txt \
  -n <your-project>

rm /tmp/pg-password.txt
```

**Step 3 — Create the LlamaStackDistribution CR**

The `VLLM_URL` must be the **internal cluster service URL** of a running InferenceService — not the external route. For a KServe InferenceService named `my-model` in namespace `demo`, the internal URL is `https://my-model-predictor.demo.svc.cluster.local:8443/v1`.

```bash
oc apply -f 05-configuration/llama-stack/llamastackdistribution-example.yaml
```

Or apply inline after customizing all `<placeholder>` values:

```bash
cat <<EOF | oc apply -f -
apiVersion: llamastack.io/v1alpha1
kind: LlamaStackDistribution
metadata:
  name: llamastack
  namespace: <your-project>
  labels:
    # Required — without this label the gen-ai-ui informer ignores the LSD
    # and the AI Playground returns "Error loading components / no LSD found"
    opendatahub.io/dashboard: "true"
spec:
  replicas: 1
  server:
    containerSpec:
      name: llama-stack
      port: 8321
      env:
        - name: VLLM_URL
          value: "https://<isvc-name>-predictor.<namespace>.svc.cluster.local:8443/v1"
        - name: INFERENCE_MODEL
          value: "<model-name>"
        - name: VLLM_TLS_VERIFY
          value: "false"
        # If the InferenceService has security.opendatahub.io/enable-auth: "true",
        # the LSD needs a bearer token. Create a non-expiring SA token secret and
        # reference it here (the SA must have 'get inferenceservices' RBAC):
        # - name: VLLM_API_TOKEN
        #   valueFrom:
        #     secretKeyRef:
        #       name: lsd-sa-token
        #       key: token
        - name: POSTGRES_HOST
          value: "<postgres-host>"
        - name: POSTGRES_PORT
          value: "5432"
        - name: POSTGRES_DB
          value: "llamastack"
        - name: POSTGRES_USER
          value: "llamastack"
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: llamastack-postgres-secret
              key: password
        # REQUIRED for AI Playground: enable the inline embedding model.
        # The rh-dev image includes ibm-granite/granite-embedding-125m-english
        # in its local cache. This registers it as the model ID the gen-ai-ui
        # expects when auto-creating the default vector store.
        - name: ENABLE_SENTENCE_TRANSFORMERS
          value: "true"
        # REQUIRED for AI Playground: enable at least one vector store backend.
        # FAISS is the simplest for dev/test (index stored in-process, metadata
        # persisted in PostgreSQL). For production RAG use ENABLE_PGVECTOR=true.
        - name: ENABLE_FAISS
          value: "true"
    distribution:
      name: rh-dev
    storage:
      size: 20Gi
EOF
```

**Verify:**

```bash
# Watch the pod start up
oc get pods -n <your-project> -l app.kubernetes.io/name=llamastackdistribution -w

# Check distribution status
oc get llamastackdistribution -n <your-project>

# Verify the Llama Stack API is responding
oc port-forward svc/llamastack -n <your-project> 8321:8321 &
curl http://localhost:8321/v1/health
```

**Reference:** [Deploying a Llama Stack server](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_llama_stack/deploying-llama-stack-server_rag)

</details>

<details>
<summary><strong>MLflow: Create an MLflow Instance (Optional)</strong></summary>

The MLflow Operator deploys an MLflow tracking server for experiment logging (metrics, parameters, artifacts) from training workloads and notebooks. The **gen-ai-studio** auto-discovers the `MLflow` CR via a cluster-wide watch and surfaces it in the UI; without a CR it gracefully returns HTTP 503 for MLflow endpoints. No other RHOAI component is blocked by missing MLflow — impact is limited to users whose code calls `mlflow.log_*()`, which will fail to connect.

**Step 1 — Enable the mlflowoperator in the DataScienceCluster**

```bash
oc patch datasciencecluster default-dsc \
  --type=merge \
  -p '{"spec":{"components":{"mlflowoperator":{"managementState":"Managed"}}}}'
```

**Step 2 — Create an MLflow CR**

```bash
oc apply -f 05-configuration/mlflow/mlflow-cr.yaml
```

Or apply the dev/test variant inline (SQLite + PVC — not for production):

```bash
cat <<EOF | oc apply -f -
apiVersion: mlflow.opendatahub.io/v1
kind: MLflow
metadata:
  name: mlflow
  namespace: redhat-ods-applications
spec:
  backendStoreUri: "sqlite:////mlflow/mlflow.db"
  serveArtifacts: true   # required when no external artifact store is configured
  storage:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 10Gi
EOF
```

> For production: use an external PostgreSQL or MySQL database (`backendStoreUri: "postgresql+psycopg2://..."`) and S3-compatible artifact storage (`defaultArtifactRoot: "s3://..."`). See `05-configuration/mlflow/mlflow-cr.yaml` for a commented production template.

**Verify:**

```bash
oc get mlflow -n redhat-ods-applications
oc get pods -n redhat-ods-applications -l app.kubernetes.io/name=mlflow
```

> **Documentation status:** The MLflow CR is documented in the official [Working with MLflow](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_mlflow) docs. The gap is that enabling `mlflowoperator: Managed` in the DSC alone is insufficient — you must also create the `MLflow` CR, and the connection to the gen-ai-studio 503 behavior is not documented.

[MLflow docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_mlflow)

</details>

<details>
<summary><strong>Kubeflow Spark Operator: Activate (Optional)</strong></summary>

```bash
# Enable in DataScienceCluster
oc patch datasciencecluster default-dsc \
  --type=merge \
  -p '{"spec":{"components":{"kubeflowsparkoperator":{"managementState":"Managed"}}}}'

# Verify KSO is running
oc get pods -n redhat-ods-applications -l app.kubernetes.io/name=kubeflow-spark-operator
```

[KSO docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/creating_distributed_data_processing_applications_with_kso)

</details>

<details>
<summary><strong>Private Cloud / OpenStack: Configure External DNS</strong></summary>

On OpenStack, CRC, or other private clouds without integrated external DNS, you must manually configure DNS A or CNAME records after the LoadBalancer IP is assigned.

```bash
oc get svc -n redhat-ods-applications | grep LoadBalancer
```

[Configuring External DNS for RHOAI 3.x on OpenStack and Private Clouds](https://access.redhat.com/articles/7133770)

</details>

<details>
<summary><strong>Certificates: Add Custom CA Bundle</strong></summary>

If your object storage, databases, or services use self-signed certificates:

```bash
oc create configmap custom-ca \
  --from-file=ca-bundle.crt=/path/to/your-ca.crt \
  -n openshift-config

oc patch proxy/cluster \
  --type=merge \
  --patch='{"spec":{"trustedCA":{"name":"custom-ca"}}}'

# Verify all namespaces got the bundle
oc get configmaps --all-namespaces -l app.kubernetes.io/part-of=opendatahub-operator | grep odh-trusted-ca-bundle
```

[Certificate configuration docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/installing_and_uninstalling_openshift_ai_self-managed/working-with-certificates_certs)

</details>

</details>

---

## Known Issues (RHOAI 3.4)

### AI Playground / GenAI Studio — "Error loading components"

**Status:** Tech Preview bug — fix in progress upstream (ODH PR #5707 / `RHOAIENG-36419`). No supported workaround exists in RHOAI 3.4.

The AI Playground crashes for all users due to a frontend null-guard bug in the `gen-ai-ui` component. The LSD backend works correctly; the issue is in how the frontend handles namespaces that lack an LSD. Open a Red Hat support case referencing `RHOAIENG-36419` (ODH Dashboard PR #5707).

---

## Key Reference Links

| Resource | URL |
|---|---|
| Install guide (main) | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/installing_and_uninstalling_openshift_ai_self-managed |
| Supported configurations | https://access.redhat.com/articles/rhoai-supported-configs-3.x |
| Life cycle / channels | https://access.redhat.com/support/policy/updates/rhoai-sm/lifecycle |
| Upgrade from 2.x to 3.x | https://access.redhat.com/articles/7133758 |
| Disconnected install guide | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/installing_and_uninstalling_openshift_ai_self-managed_in_a_disconnected_environment |
| Managing OpenShift AI (admin tasks) | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/managing_openshift_ai |
| Getting started guide | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/getting_started_with_red_hat_openshift_ai_self-managed |
| Fraud detection tutorial | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/openshift_ai_tutorial_-_fraud_detection_example |
| Distributed Inference with llm-d | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/deploy_models_using_distributed_inference_with_llm-d/deploying-models-using-distributed-inference_distributed-inference#enabling-distributed-inference_distributed-inference |
| MLflow docs | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_mlflow |
| Kubeflow Spark Operator docs | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/creating_distributed_data_processing_applications_with_kso |
| Working with Llama Stack | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_llama_stack/deploying-llama-stack-server_rag |
