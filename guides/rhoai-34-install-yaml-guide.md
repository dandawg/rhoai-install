# RHOAI 3.4 — YAML Install Guide

CLI-first installation of **Red Hat OpenShift AI Self-Managed 3.4** using `oc apply -f`.
This guide mirrors the phase structure of the [field guide](rhoai-34-install-field-guide.md) but replaces every OperatorHub GUI step with `oc apply -f` commands against the YAML files in this repository.

Use this alongside the [official install documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/installing_and_uninstalling_openshift_ai_self-managed).

**Companion scripts** (run from the repo root):

```bash
bash guides/rhoai-prerequisites-check.sh   # Phase 0 — cluster pre-validation
bash guides/rhoai-dependency-check.sh      # Phase 1 — operator dependency validation
```

**Last updated:** May 2026 · Based on RHOAI 3.4 and the latest published Red Hat documentation

---

## Quick Reference

| Item | Value |
|---|---|
| Min OCP Version | 4.19 (4.20 required for llm-d Distributed Inference) |
| Operator Channel | `stable-3.x` |
| Operator Namespace | `redhat-ods-operator` |
| Apps Namespace | `redhat-ods-applications` |
| Default Workbench Namespace | `rhods-notebooks` |

> **Upgrade note:** Upgrades from RHOAI 2.x → 3.x are not directly supported. See the [Upgrade KB article](https://access.redhat.com/articles/7133758).
> Do NOT install more than one RHOAI instance per cluster.

---

<details>
<summary><strong>Phase 0: Cluster Pre-Validation</strong></summary>

Run from the repo root. Log in as a non-`kubeadmin` cluster-admin user first.

```bash
bash guides/rhoai-prerequisites-check.sh
```

The script exits `0` when all checks pass. Output legend: `✓ OK` · `✗ FAIL` · `⚠ WARN` · `ℹ VERIFY`

**Manual commands** are in [`00-prerequisites/README.md`](../00-prerequisites/README.md).

### Pre-Validation Checklist

| Check | Pass Criteria | Required |
|---|---|---|
| OCP version | 4.19 or 4.20 | **Required** |
| Worker nodes | 2+ nodes × 8 CPU + 32 GiB RAM (SNO: 32 CPU + 128 GiB) | **Required** |
| Default StorageClass | Marked `(default)`, dynamic provisioning | **Required** |
| Identity Provider | At least one IdP (not just kubeadmin) | **Required** |
| cluster-admin user | Non-`kubeadmin` user with `cluster-admin` role | **Required** |
| Open Data Hub | NOT installed | **Required** |
| Network (from nodes) | `registry.redhat.io`, `quay.io`, `cdn.redhat.com` reachable from worker nodes | **Required** |
| RHOAI subscription | Valid Red Hat OpenShift AI Self-Managed entitlement | **Required** |

### Optional prerequisites (by component)

Plan these before enabling the matching DataScienceCluster components — they are not required to install RHOAI:

| If you enable… | Also need… |
|---|---|
| `aipipelines` | S3-compatible object storage |
| `modelregistry` | MySQL 5.x+ (8.x recommended) and S3 |
| `mlflowoperator` (production) | External DB and S3 |
| GPU / llm-d workloads | GPU nodes and optional dependency operators (NFD, GPU operator, LWS, etc.) |
| `llamastackoperator` | Service Mesh 3.x, cert-manager, GPU, and NFD |

Model serving (`kserve`) does not require object storage — models can use PVC, OCI, S3, or inline sources.

</details>

---

<details>
<summary><strong>Phase 1: Required Dependency Operators</strong></summary>

Install all six operators before installing the RHOAI operator.

| # | Operator | Namespace | CR required? | Apply path |
|---|---|---|---|---|
| 1 | cert-manager | `cert-manager-operator` | No | `01-required-dependencies/cert-manager/` |
| 2 | Job Set | `openshift-jobset-operator` | **Yes** — `JobSetOperator` | `01-required-dependencies/job-set/` |
| 3 | Custom Metrics Autoscaler (KEDA) | `openshift-keda` | No (auto-created) | `01-required-dependencies/custom-metrics-autoscaler/` |
| 4 | Red Hat build of OpenTelemetry | `openshift-opentelemetry-operator` | No | `01-required-dependencies/opentelemetry/` |
| 5 | Tempo Operator | `openshift-tempo-operator` | No | `01-required-dependencies/tempo/` |
| 6 | Cluster Observability Operator | `openshift-cluster-observability-operator` | No | `01-required-dependencies/cluster-observability/` |

> **Note on cert-manager:** Apply cert-manager first since subsequent operators (LWS, kserve) depend on it.

### 1. cert-manager Operator

```bash
oc apply -f 01-required-dependencies/cert-manager/
```

**Verify:**

```bash
oc get pods -n cert-manager
# Expected: 3 pods Running (cert-manager, cainjector, webhook)
```

---

### 2. Job Set Operator

The operator namespace and OperatorGroup must exist before the subscription:

```bash
oc apply -f 01-required-dependencies/job-set/namespace.yaml
oc apply -f 01-required-dependencies/job-set/operatorgroup.yaml
oc apply -f 01-required-dependencies/job-set/subscription.yaml
```

Wait for the CSV to reach `Succeeded`:

```bash
oc get csv -n openshift-jobset-operator -w
# Ctrl+C once STATUS = Succeeded
```

**Create the required CR** (operator is non-functional until this is applied):

```bash
oc apply -f 01-required-dependencies/job-set/jobsetoperator-cr.yaml
```

**Verify:**

```bash
oc get JobSetOperator cluster
oc get pods -n openshift-jobset-operator
```

---

### 3. Custom Metrics Autoscaler (KEDA)

```bash
oc apply -f 01-required-dependencies/custom-metrics-autoscaler/
```

**Verify:**

```bash
oc get pods -n openshift-keda
oc get KedaController -n openshift-keda   # auto-created by operator
```

---

### 4. Red Hat build of OpenTelemetry

```bash
oc apply -f 01-required-dependencies/opentelemetry/
```

**Verify:**

```bash
oc get csv -n openshift-opentelemetry-operator
oc get pods -n openshift-opentelemetry-operator
```

> **Note:** Required when DSCI observability features are enabled. See [01-required-dependencies/README.md](../01-required-dependencies/README.md) for context.

---

### 5. Tempo Operator

```bash
oc apply -f 01-required-dependencies/tempo/
```

**Verify:**

```bash
oc get csv -n openshift-tempo-operator
oc get pods -n openshift-tempo-operator
```

---

### 6. Cluster Observability Operator

```bash
oc apply -f 01-required-dependencies/cluster-observability/
```

**Verify:**

```bash
oc get csv -n openshift-cluster-observability-operator
oc get pods -n openshift-cluster-observability-operator
```

---

### Validate All Required Dependencies

```bash
bash guides/rhoai-dependency-check.sh
```

All six required operators must show `✓ READY` before continuing to optional deps or Phase 2.

</details>

---

<details>
<summary><strong>Phase 1b: Optional Dependency Operators</strong></summary>

Install only the operators relevant to your environment. See [02-optional-dependencies/README.md](../02-optional-dependencies/README.md) for the full selection guide.

| Operator | Namespace | CR required? | Apply path | When needed |
|---|---|---|---|---|
| NFD | `openshift-nfd` | **Yes** — `NodeFeatureDiscovery` | `02-optional-dependencies/nfd/` | GPU nodes (install before GPU operators) |
| NVIDIA GPU Operator | `nvidia-gpu-operator` | **Yes** — `ClusterPolicy` | `02-optional-dependencies/nvidia-gpu/` | NVIDIA GPU nodes |
| Red Hat build of Kueue | `openshift-kueue-operator` | **Yes** — `Kueue` (`cluster`) | `02-optional-dependencies/kueue/` | Ray, TrainingOperator, batch workloads |
| Leader Worker Set (LWS) | `openshift-lws-operator` | **Yes** — `LeaderWorkerSetOperator` | `02-optional-dependencies/lws/` | llm-d Distributed Inference |
| OpenShift Service Mesh 3.x | `openshift-operators` | No (RHOAI creates CR) | `02-optional-dependencies/service-mesh/` | Llama Stack / RAG |
| SR-IOV Network Operator | `openshift-sriov-network-operator` | No (auto-created) | `02-optional-dependencies/sriov/` | SR-IOV / RDMA multi-node GPU |
| Red Hat Connectivity Link (RHCL) | `openshift-operators` | No (Gateway in Post-Install) | `02-optional-dependencies/rhcl/` | llm-d Distributed Inference |

> **Install ordering:** NFD before NVIDIA GPU. LWS requires cert-manager already running.

---

### NFD — Node Feature Discovery

**When needed:** Any cluster with GPU nodes.

```bash
oc apply -f 02-optional-dependencies/nfd/namespace.yaml
oc apply -f 02-optional-dependencies/nfd/operatorgroup.yaml
oc apply -f 02-optional-dependencies/nfd/subscription.yaml
```

Wait for CSV:

```bash
oc get csv -n openshift-nfd -w
```

**Create CR** (required):

```bash
oc apply -f 02-optional-dependencies/nfd/nfd-instance.yaml
```

**Verify:**

```bash
oc get NodeFeatureDiscovery -n openshift-nfd
NODE=$(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[0].metadata.name}')
oc describe node $NODE | grep "feature.node.kubernetes.io" | head -5
```

---

### NVIDIA GPU Operator

**When needed:** NVIDIA GPU nodes. NFD must be installed and running first.

```bash
oc apply -f 02-optional-dependencies/nvidia-gpu/namespace.yaml
oc apply -f 02-optional-dependencies/nvidia-gpu/operatorgroup.yaml
oc apply -f 02-optional-dependencies/nvidia-gpu/subscription.yaml
```

Wait for CSV:

```bash
oc get csv -n nvidia-gpu-operator -w
```

**Create CR** (required):

```bash
oc apply -f 02-optional-dependencies/nvidia-gpu/clusterpolicy.yaml
```

**Verify** (GPU driver load takes ~5 minutes):

```bash
oc get ClusterPolicy gpu-cluster-policy
oc get pods -n nvidia-gpu-operator
oc describe node <gpu-node-name> | grep "nvidia.com/gpu"
# Expected: nvidia.com/gpu: <N> in Capacity and Allocatable
```

---

### Red Hat build of Kueue

**When needed:** Distributed workloads (Ray, TrainingOperator).

```bash
oc apply -f 02-optional-dependencies/kueue/namespace.yaml
oc apply -f 02-optional-dependencies/kueue/operatorgroup.yaml
oc apply -f 02-optional-dependencies/kueue/subscription.yaml
```

Wait for CSV:

```bash
oc get csv -n openshift-kueue-operator -w
```

Edit `kueue-cr.yaml` to add your required frameworks, then **create CR** (required; name must be `cluster`):

```bash
oc apply -f 02-optional-dependencies/kueue/kueue-cr.yaml
```

**Verify:**

```bash
oc get Kueue cluster -n openshift-kueue-operator
oc get pods -n openshift-kueue-operator | grep kueue-controller-manager
```

> **DSC note:** When Kueue operator is installed, set `kueue.managementState: Unmanaged` in the DataScienceCluster (see Phase 3).

---

### Red Hat Leader Worker Set (LWS)

**When needed:** Distributed Inference with llm-d. cert-manager must be running.

```bash
oc apply -f 02-optional-dependencies/lws/namespace.yaml
oc apply -f 02-optional-dependencies/lws/operatorgroup.yaml
oc apply -f 02-optional-dependencies/lws/subscription.yaml
```

Wait for CSV:

```bash
oc get csv -n openshift-lws-operator -w
```

**Create CR** (required):

```bash
oc apply -f 02-optional-dependencies/lws/lws-cr.yaml
```

**Verify:**

```bash
oc get LeaderWorkerSetOperator cluster
oc get pods -n openshift-lws-operator
```

---

### OpenShift Service Mesh 3.x

**When needed:** Llama Stack / RAG (`llamastackoperator: Managed` in DSC).

```bash
oc apply -f 02-optional-dependencies/service-mesh/subscription.yaml
```

**Verify:**

```bash
oc get csv -n openshift-operators | grep servicemesh
```

---

### SR-IOV Network Operator

**When needed:** SR-IOV capable NICs / RDMA workloads (e.g. GPU-to-GPU over InfiniBand or RoCE). Not required for standard Ethernet GPU workloads.

```bash
oc apply -f 02-optional-dependencies/sriov/namespace.yaml
oc apply -f 02-optional-dependencies/sriov/operatorgroup.yaml
oc apply -f 02-optional-dependencies/sriov/subscription.yaml
```

Wait for CSV:

```bash
oc get csv -n sriov-network-operator -w
```

**Verify:**

```bash
oc get SriovOperatorConfig default -n sriov-network-operator
oc get pods -n sriov-network-operator
```

After the operator is running, create `SriovNetworkNodePolicy` resources to configure VFs on SR-IOV capable nodes. See the [SR-IOV Network Operator docs](https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/networking/hardware-networks#about-sriov).

---

### Red Hat Connectivity Link (RHCL)

**When needed:** Distributed Inference with llm-d.

```bash
oc apply -f 02-optional-dependencies/rhcl/subscription.yaml
```

**Verify:**

```bash
oc get subscription rhcl-operator -n openshift-operators
```

After RHOAI is installed and the DSC is applied, configure the Gateway resources in Phase 5.

---

### Validate All Dependencies

```bash
bash guides/rhoai-dependency-check.sh
```

</details>

---

<details>
<summary><strong>Phase 2: Install the RHOAI Operator</strong></summary>

All Phase 1 required operators must be healthy before proceeding.

```bash
oc apply -f 03-rhoai-operator/
```

This applies: Namespace (`redhat-ods-operator`), OperatorGroup (AllNamespaces), Subscription (`stable-3.x`).

### Verify Operator Installed

Watch the CSV reach `Succeeded` (takes 2–5 minutes):

```bash
oc get csv -n redhat-ods-operator -w
```

Confirm:

```bash
oc get pods -n redhat-ods-operator
# Expected: rhods-operator pod Running

oc get subscription rhods-operator -n redhat-ods-operator -o jsonpath='{.status.installedCSV}{"\n"}'
# Expected: rhods-operator.3.4.x
```

See [03-rhoai-operator/README.md](../03-rhoai-operator/README.md) for channel options.

</details>

---

<details>
<summary><strong>Phase 3: Configure the DataScienceCluster</strong></summary>

Create the `DataScienceCluster` CR to install and enable RHOAI components.

### Choose a configuration

| File | When to use |
|---|---|
| `04-datasciencecluster/datasciencecluster.yaml` | Default — edit `managementState` values for your environment |
| `04-datasciencecluster/variants/datasciencecluster-minimal.yaml` | Quick start — dashboard, workbenches, kserve, aipipelines only |
| `04-datasciencecluster/variants/datasciencecluster-gpu-kueue.yaml` | GPU + distributed workloads — requires NFD, GPU, Kueue operators |

**Edit the file before applying** — review each component's `managementState` and prerequisites.

Key decisions:
- If Kueue operator is installed → set `kueue.managementState: Unmanaged`
- If no Kueue operator → set `kueue.managementState: Removed`
- Remove components you don't need (reduce startup time and resource usage)

```bash
# Apply default configuration (after editing):
oc apply -f 04-datasciencecluster/datasciencecluster.yaml

# Or a variant:
oc apply -f 04-datasciencecluster/variants/datasciencecluster-minimal.yaml
```

### Component Reference

| Component | managementState | Prerequisites |
|---|---|---|
| `dashboard` | **Managed** | None |
| `workbenches` | Managed / Removed | Default StorageClass |
| `aipipelines` | Managed / Removed | S3 storage |
| `kserve` | Managed / Removed | cert-manager |
| `kueue` | **Unmanaged** (if Kueue operator) / Removed | Kueue operator |
| `ray` | Managed / Removed | Kueue + cert-manager |
| `trainer` | Managed / Removed | Job Set operator |
| `trainingoperator` | Removed (legacy) | Kueue + cert-manager |
| `modelregistry` | Managed / Removed | MySQL (prod) |
| `trustyai` | Managed / Removed | None |
| `llamastackoperator` | Managed / Removed | Service Mesh 3.x + cert-manager + GPU + NFD |
| `mlflowoperator` | Managed / Removed | PVC (dev) or DB + S3 (prod) |
| `feastoperator` | Managed / Removed | None |
| `sparkoperator` | Removed | Custom Spark image |

### Verify Components

```bash
# Watch until phase is Ready (5–10 minutes)
oc get datasciencecluster default-dsc -w

# Check phase
oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}{"\n"}'
# Expected: Ready

# Check pods
oc get pods -n redhat-ods-applications
```

</details>

---

<details>
<summary><strong>Phase 4: Configure User Access</strong></summary>

Optional — skip to allow all OpenShift users to access RHOAI.

```bash
# Create user groups
oc apply -f 05-configuration/user-access/groups.yaml

# Add users
oc adm groups add-users rhods-users <username>
oc adm groups add-users rhods-admins <admin-username>
```

Then configure RHOAI to use these groups:
**RHOAI Dashboard → Settings → User management**

See [05-configuration/README.md](../05-configuration/README.md) for details.

</details>

---

<details>
<summary><strong>Phase 5: Dashboard Access &amp; Final Validation</strong></summary>

```bash
# Get the dashboard URL (RHOAI 3.4+)
echo "https://rh-ai.$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}')"
```

> **Note:** Starting with RHOAI 3.4, the dashboard is served via the Gateway API and the URL follows the format `https://rh-ai.apps.<cluster-domain>`. The command above reads the cluster's ingress domain directly to construct it. Running `oc get route -n redhat-ods-applications` will only show legacy redirect routes (`rhods-dashboard`, `data-science-gateway`) that redirect to this new URL — they are not the canonical endpoint.

### Final Validation Checklist

| Validation | Command / Action | Expected |
|---|---|---|
| Dashboard loads | Open RHOAI dashboard URL in browser | Login page, login succeeds |
| Components visible | Dashboard → Help → About | All enabled components listed |
| DSC Ready | `oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}'` | `Ready` |
| Pods healthy | `oc get pods -n redhat-ods-applications` | No CrashLoopBackOff or Error |
| GPU detected (if GPU nodes) | `oc describe node <gpu-node> \| grep nvidia.com/gpu` | GPU in Capacity and Allocatable |
| Kueue running (if installed) | `oc get pods -n openshift-kueue-operator` | `kueue-controller-manager` Running |
| Non-admin login | Log in as a data scientist user | Dashboard visible with projects |

</details>

---

<details>
<summary><strong>Post-Install: Component-Specific Configuration</strong></summary>

<details>
<summary><strong>Hardware Profiles</strong></summary>

Create hardware profiles so data scientists can select GPU resources when deploying models or running workbenches.

**RHOAI Dashboard → Settings → Environment setup → Hardware profiles → Add hardware profile**

See [Hardware profiles docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_accelerators/working-with-hardware-profiles_accelerators).

</details>

<details>
<summary><strong>AI Pipelines: Configure Object Storage</strong></summary>

**RHOAI Dashboard → Data Science Projects → [project] → Connections → Add connection → S3-compatible object storage**

Then: Data Science Projects → [project] → Pipelines → Configure pipeline server

See [AI Pipelines docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_ai_pipelines).

</details>

<details>
<summary><strong>Distributed Workloads (Kueue): Configure Queues</strong></summary>

After installing the Kueue operator and applying the DSC with `kueue: Unmanaged`:

```bash
# Edit clusterqueue.yaml first — set cpu/memory/GPU quotas for your cluster
oc apply -f 05-configuration/distributed-workloads/clusterqueue.yaml

# Create a LocalQueue in each project namespace where workloads will run
oc apply -f 05-configuration/distributed-workloads/localqueue.yaml -n <project-namespace>
```

See [Distributed workloads docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/managing_openshift_ai/managing-distributed-workloads_managing-rhoai).

</details>

<details>
<summary><strong>Distributed Inference (llm-d): Configure Gateway</strong></summary>

**Requirements:** LWS operator, RHCL operator, kserve Managed, OCP 4.20+. Service Mesh v2 must NOT be installed.

```bash
# Create GatewayClass (once per cluster)
oc apply -f 05-configuration/llm-d/gateway-class.yaml

# Create the shared Gateway
oc apply -f 05-configuration/llm-d/gateway.yaml
```

See [Enabling Distributed Inference with llm-d](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/deploy_models_using_distributed_inference_with_llm-d/deploying-models-using-distributed-inference_distributed-inference#enabling-distributed-inference_distributed-inference).

</details>

<details>
<summary><strong>Certificates: Add Custom CA Bundle</strong></summary>

If your object storage or services use self-signed certificates:

```bash
oc create configmap custom-ca \
  --from-file=ca-bundle.crt=/path/to/your-ca.crt \
  -n openshift-config

oc patch proxy/cluster \
  --type=merge \
  --patch='{"spec":{"trustedCA":{"name":"custom-ca"}}}'

# Verify all namespaces received the bundle
oc get configmaps --all-namespaces -l app.kubernetes.io/part-of=opendatahub-operator | grep odh-trusted-ca-bundle
```

See [Certificate configuration docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/installing_and_uninstalling_openshift_ai_self-managed/working-with-certificates_certs).

</details>

</details>

---

## Key Reference Links

| Resource | URL |
|---|---|
| Install guide (main) | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/installing_and_uninstalling_openshift_ai_self-managed |
| Supported configurations | https://access.redhat.com/articles/rhoai-supported-configs-3.x |
| Life cycle / channels | https://access.redhat.com/support/policy/updates/rhoai-sm/lifecycle |
| Upgrade from 2.x to 3.x | https://access.redhat.com/articles/7133758 |
| Disconnected install guide | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/installing_and_uninstalling_openshift_ai_self-managed_in_a_disconnected_environment |
| Managing OpenShift AI | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/managing_openshift_ai |
| Distributed Inference with llm-d | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/deploy_models_using_distributed_inference_with_llm-d/deploying-models-using-distributed-inference_distributed-inference#enabling-distributed-inference_distributed-inference |
| MLflow docs | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_mlflow |
| Kubeflow Spark Operator docs | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/creating_distributed_data_processing_applications_with_kso |
| Working with Llama Stack | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_llama_stack |
