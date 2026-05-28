# Phase 1b: Optional Dependencies

Install only the operators relevant to your environment. Each section is self-contained with Install → Configure → Verify steps.

> **Install ordering matters for some operators:** NFD must be installed and running before the NVIDIA GPU Operator. LWS requires cert-manager to already be running (installed in Phase 1).

After installing your chosen optional operators, run the dependency check again:

```bash
bash guides/rhoai-dependency-check.sh
```

---

## Operator Selection Guide

| Operator | Install When | Prerequisite |
|---|---|---|
| [NFD](#nfd--node-feature-discovery) | Any cluster with GPU nodes | — |
| [NVIDIA GPU Operator](#nvidia-gpu-operator) | NVIDIA GPU nodes | NFD running |
| [Red Hat build of Kueue](#red-hat-build-of-kueue) | Distributed workloads (Ray, TrainingOperator) | — |
| [Leader Worker Set (LWS)](#red-hat-leader-worker-set-operator) | Distributed Inference with llm-d | cert-manager running |
| [OpenShift Service Mesh 3.x](#openshift-service-mesh-3x) | Llama Stack / RAG | — |
| [SR-IOV Network Operator](#sr-iov-network-operator) | SR-IOV NICs / RDMA workloads | SR-IOV capable hardware |
| [Red Hat Connectivity Link (RHCL)](#red-hat-connectivity-link-operator) | llm-d Gateway | — |

---

## NFD — Node Feature Discovery

**When needed:** Any cluster with GPU nodes. Must be installed before the GPU operator.

| | |
|---|---|
| Package | `nfd` |
| Namespace | `openshift-nfd` |
| Channel | `stable` |
| CR required? | **Yes** — `NodeFeatureDiscovery` CR named `nfd-instance` |

```bash
oc apply -f 02-optional-dependencies/nfd/namespace.yaml
oc apply -f 02-optional-dependencies/nfd/operatorgroup.yaml
oc apply -f 02-optional-dependencies/nfd/subscription.yaml
```

Wait for CSV to reach `Succeeded`:

```bash
oc get csv -n openshift-nfd -w
```

**Create CR:**

```bash
oc apply -f 02-optional-dependencies/nfd/nfd-instance.yaml
```

**Verify** (labels appear on nodes within ~2 minutes):

```bash
oc get NodeFeatureDiscovery -n openshift-nfd
NODE=$(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[0].metadata.name}')
oc describe node $NODE | grep "feature.node.kubernetes.io" | head -5
```

---

## NVIDIA GPU Operator

**When needed:** Clusters with NVIDIA GPU nodes. Requires NFD running first.

| | |
|---|---|
| Package | `gpu-operator-certified` |
| Namespace | `nvidia-gpu-operator` |
| Channel | `stable` (latest stable CSV in channel; no `startingCSV` pin) |
| Source | `certified-operators` |
| CR required? | **Yes** — `ClusterPolicy` CR named `gpu-cluster-policy` |

```bash
oc apply -f 02-optional-dependencies/nvidia-gpu/namespace.yaml
oc apply -f 02-optional-dependencies/nvidia-gpu/operatorgroup.yaml
oc apply -f 02-optional-dependencies/nvidia-gpu/subscription.yaml
```

Wait for CSV to reach `Succeeded`:

```bash
oc get csv -n nvidia-gpu-operator -w
```

**Create CR:**

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

To use a specific release train instead of `stable`, set `spec.channel` in `subscription.yaml` to a version channel from OperatorHub (for example `v26.3`). See [NVIDIA GPU Operator on OpenShift](https://docs.nvidia.com/datacenter/cloud-native/openshift/latest/openshift-release-notes.html).

---

## Red Hat build of Kueue

**When needed:** Distributed workloads using Ray, Kubeflow TrainingOperator, or other batch frameworks.

| | |
|---|---|
| Package | `kueue-operator` |
| Namespace | `openshift-kueue-operator` |
| Channel | `stable-v1.2` |
| CR required? | **Yes** — `Kueue` CR named `cluster`; name must be `cluster` |

> **DSC note:** When this operator is installed, set `kueue.managementState: Unmanaged` in the DataScienceCluster (see [04-datasciencecluster](../04-datasciencecluster/README.md)). This lets the external Kueue operator own the instance.

```bash
oc apply -f 02-optional-dependencies/kueue/namespace.yaml
oc apply -f 02-optional-dependencies/kueue/operatorgroup.yaml
oc apply -f 02-optional-dependencies/kueue/subscription.yaml
```

Wait for CSV to reach `Succeeded`:

```bash
oc get csv -n openshift-kueue-operator -w
```

**Create CR:**

```bash
oc apply -f 02-optional-dependencies/kueue/kueue-cr.yaml
```

Edit `kueue-cr.yaml` first to add frameworks for your workloads (`RayJob`, `RayCluster`, `PyTorchJob`, etc.).

**Verify:**

```bash
oc get Kueue cluster -n openshift-kueue-operator
oc get pods -n openshift-kueue-operator | grep kueue-controller-manager
```

After Kueue is running, configure queues in [05-configuration/distributed-workloads](../05-configuration/distributed-workloads/).

---

## Red Hat Leader Worker Set Operator

**When needed:** Distributed Inference with llm-d. Requires cert-manager already running (installed in Phase 1).

| | |
|---|---|
| Package | `leader-worker-set` |
| Namespace | `openshift-lws-operator` |
| Channel | `stable-v1.0` |
| CR required? | **Yes** — `LeaderWorkerSetOperator` CR named `cluster` |

```bash
oc apply -f 02-optional-dependencies/lws/namespace.yaml
oc apply -f 02-optional-dependencies/lws/operatorgroup.yaml
oc apply -f 02-optional-dependencies/lws/subscription.yaml
```

Wait for CSV:

```bash
oc get csv -n openshift-lws-operator -w
```

**Create CR:**

```bash
oc apply -f 02-optional-dependencies/lws/lws-cr.yaml
```

**Verify:**

```bash
oc get LeaderWorkerSetOperator cluster
oc get pods -n openshift-lws-operator
```

---

## OpenShift Service Mesh 3.x

**When needed:** Llama Stack / RAG workloads (`llamastackoperator: Managed` in the DSC).

| | |
|---|---|
| Package | `servicemeshoperator3` |
| Namespace | `openshift-operators` (cluster-scoped, no separate namespace/OG needed) |
| Channel | `stable` |
| CR required? | No — RHOAI creates the `ServiceMesh` CR automatically when Llama Stack is enabled in the DSC |

```bash
oc apply -f 02-optional-dependencies/service-mesh/subscription.yaml
```

**Verify:**

```bash
oc get subscription servicemeshoperator3 -n openshift-operators
oc get csv -n openshift-operators | grep servicemesh
```

---

## SR-IOV Network Operator

**When needed:** Clusters with SR-IOV capable NICs where workloads require high-performance networking via RDMA (e.g. GPU-to-GPU communication over InfiniBand or RoCE). Not required for standard Ethernet GPU workloads.

|| |
|---|---|
| Package | `sriov-network-operator` |
| Namespace | `sriov-network-operator` |
| Channel | `stable` |
| Source | `redhat-operators` |
| CR required? | No — `SriovOperatorConfig` CR named `default` is auto-created by the operator. `SriovNetworkNodePolicy` resources are created per-node to configure VFs. |

```bash
oc apply -f 02-optional-dependencies/sriov/namespace.yaml
oc apply -f 02-optional-dependencies/sriov/operatorgroup.yaml
oc apply -f 02-optional-dependencies/sriov/subscription.yaml
```

Wait for CSV to reach `Succeeded`:

```bash
oc get csv -n sriov-network-operator -w
```

**Verify:**

```bash
oc get SriovOperatorConfig default -n sriov-network-operator
oc get pods -n sriov-network-operator
```

After the operator is running, create `SriovNetworkNodePolicy` resources to configure SR-IOV Virtual Functions (VFs) on your nodes. See the [SR-IOV Network Operator documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/networking/hardware-networks#about-sriov) for policy examples and node configuration.

---

## Red Hat Connectivity Link Operator

**When needed:** Distributed Inference with llm-d. After installing, configure GatewayClass and Gateway resources in [05-configuration/llm-d](../05-configuration/llm-d/).

| | |
|---|---|
| Package | `rhcl-operator` |
| Namespace | `openshift-operators` (cluster-scoped, no separate namespace/OG needed) |
| Channel | `stable` |
| CR required? | No — Gateway resources are configured separately in post-install |

```bash
oc apply -f 02-optional-dependencies/rhcl/subscription.yaml
```

**Verify:**

```bash
oc get subscription rhcl-operator -n openshift-operators
```

---

## Next Step

Once your optional operators are installed and verified, proceed to [Phase 2: RHOAI Operator](../03-rhoai-operator/README.md).
