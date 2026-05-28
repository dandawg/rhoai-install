# rhoai-install

RHOAI 3.4 installation accelerator provides YAML manifests and installation guides organized in documentation order to help install **Red Hat OpenShift AI Self-Managed 3.4** on OpenShift 4.19+.

## Purpose

This repo accelerates manual RHOAI installs by providing:
- **YAML files** for every operator and resource, organized by install phase
- **Installation guides** for both GUI-based and CLI/YAML-based installs
- **Pre-flight and validation scripts** to check readiness before and after each phase
- **An optional ArgoCD path** (`gitops/`) for teams already running Argo CD

This repo follows the official RHOAI documentation structure and order, using plain `oc apply -f` as the primary install interface.

---

## Prerequisites

- OpenShift 4.19+ cluster with cluster-admin access (non-`kubeadmin` user)
- `oc` CLI installed and logged in
- Valid Red Hat OpenShift AI Self-Managed subscription
- Default StorageClass with dynamic provisioning

See [`00-prerequisites/README.md`](00-prerequisites/README.md) for the full pre-flight checklist.

## Optional prerequisites (by component)

Plan these before enabling the corresponding DataScienceCluster components — they are not required to install RHOAI itself:

| If you enable… | Also need… |
|---|---|
| `aipipelines` | S3-compatible object storage |
| `modelregistry` | MySQL 5.x+ (8.x recommended) and S3 |
| `mlflowoperator` (production) | External DB and S3 |
| GPU / llm-d workloads | GPU nodes and optional dependency operators (NFD, GPU operator, LWS, etc.) |
| `llamastackoperator` | Service Mesh 3.x, cert-manager, GPU, and NFD |

Model serving (`kserve`) does not require object storage — models can use PVC, OCI, S3, or inline sources.

---

## Quick Start — CLI / YAML Install

```bash
# 0. Validate cluster readiness
bash guides/rhoai-prerequisites-check.sh

# 1. Install required dependency operators
oc apply -f 01-required-dependencies/cert-manager/
oc apply -f 01-required-dependencies/job-set/namespace.yaml
oc apply -f 01-required-dependencies/job-set/operatorgroup.yaml
oc apply -f 01-required-dependencies/job-set/subscription.yaml
# (wait for CSV Succeeded, then:)
oc apply -f 01-required-dependencies/job-set/jobsetoperator-cr.yaml
oc apply -f 01-required-dependencies/custom-metrics-autoscaler/
oc apply -f 01-required-dependencies/opentelemetry/
oc apply -f 01-required-dependencies/tempo/
oc apply -f 01-required-dependencies/cluster-observability/

# Validate Phase 1
bash guides/rhoai-dependency-check.sh

# 1b. Install optional dependencies (only those relevant to your environment)
#   - GPU nodes:        02-optional-dependencies/nfd/ then nvidia-gpu/
#   - Dist. workloads:  02-optional-dependencies/kueue/
#   - llm-d inference:  02-optional-dependencies/lws/ and rhcl/
#   - Llama Stack:      02-optional-dependencies/service-mesh/

# 2. Install the RHOAI operator
oc apply -f 03-rhoai-operator/
# (wait for: oc get csv -n redhat-ods-operator -w → Succeeded)

# 3. Configure and apply the DataScienceCluster
#   Edit datasciencecluster.yaml first — set managementState for each component
oc apply -f 04-datasciencecluster/datasciencecluster.yaml
# (wait for: oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}' → Ready)

# 4. (Optional) Configure user access
oc apply -f 05-configuration/user-access/groups.yaml

# 5. Get the dashboard URL
oc get route -n redhat-ods-applications | grep rhods-dashboard
```

---

## Repository Structure

```
rhoai-install/
├── guides/
│   ├── rhoai-34-install-field-guide.md      GUI + CLI install guide (RHOAI 3.4)
│   ├── rhoai-34-install-yaml-guide.md       YAML-first install guide (this repo)
│   ├── rhoai-prerequisites-check.sh         Phase 0 cluster validation script
│   └── rhoai-dependency-check.sh            Phase 1 operator validation script
├── 00-prerequisites/
│   └── README.md                            Pre-flight checklist and manual commands
├── 01-required-dependencies/
│   ├── README.md                            Install + validate instructions
│   ├── cert-manager/                        Namespace, OG, Subscription
│   ├── job-set/                             Namespace, OG, Subscription, JobSetOperator CR
│   ├── custom-metrics-autoscaler/           Namespace, OG, Subscription
│   ├── opentelemetry/                       Namespace, OG, Subscription
│   ├── tempo/                               Namespace, OG, Subscription
│   └── cluster-observability/              Namespace, OG, Subscription
├── 02-optional-dependencies/
│   ├── README.md                            Selection guide + install instructions
│   ├── nfd/                                 NFD operator + NodeFeatureDiscovery CR
│   ├── nvidia-gpu/                          GPU operator + ClusterPolicy CR
│   ├── kueue/                               Kueue operator + Kueue CR
│   ├── lws/                                 Leader Worker Set operator + CR
│   ├── service-mesh/                        Service Mesh 3.x subscription
│   └── rhcl/                               Connectivity Link subscription
├── 03-rhoai-operator/
│   ├── README.md                            Install + verify instructions
│   ├── namespace.yaml
│   ├── operatorgroup.yaml
│   └── subscription.yaml                   channel: stable-3.x
├── 04-datasciencecluster/
│   ├── README.md                            Component reference + verify instructions
│   ├── datasciencecluster.yaml              Default configuration
│   └── variants/
│       ├── datasciencecluster-minimal.yaml  Core components only
│       └── datasciencecluster-gpu-kueue.yaml GPU + distributed workloads
├── 05-configuration/
│   ├── README.md                            Post-install configuration guidance
│   ├── user-access/groups.yaml              RHOAI user/admin groups
│   ├── distributed-workloads/               ClusterQueue + LocalQueue for Kueue
│   └── llm-d/                              GatewayClass + Gateway for llm-d
└── gitops/                                  ArgoCD path (optional — see below)
    ├── README.md
    ├── rhoai-required-deps.yaml
    ├── rhoai-optional-deps.yaml
    ├── rhoai-operator.yaml
    └── rhoai-datasciencecluster.yaml
```

---

## Guides

| Guide | Description |
|---|---|
| [`guides/rhoai-34-install-field-guide.md`](guides/rhoai-34-install-field-guide.md) | Primary field guide — GUI + CLI steps, all phases, post-install config |
| [`guides/rhoai-34-install-yaml-guide.md`](guides/rhoai-34-install-yaml-guide.md) | YAML-first guide — replaces GUI steps with `oc apply -f` commands pointing at this repo |

Both guides use the same 5-phase structure matching the official RHOAI documentation.

---

## ArgoCD Path (Optional)

For teams already running Argo CD, the `gitops/` directory contains ArgoCD `Application` manifests that point at the same numbered directories used by the manual install path — no file duplication.

See [`gitops/README.md`](gitops/README.md) for setup instructions.

The manual install path is the primary path; `gitops/` is a convenience layer that does not interfere with it.

---

## Official Documentation

| Resource | URL |
|---|---|
| Install guide (main) | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/installing_and_uninstalling_openshift_ai_self-managed |
| Supported configurations | https://access.redhat.com/articles/rhoai-supported-configs-3.x |
| Life cycle / channels | https://access.redhat.com/support/policy/updates/rhoai-sm/lifecycle |
| Managing OpenShift AI | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/managing_openshift_ai |
