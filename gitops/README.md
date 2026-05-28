# ArgoCD Path (Optional)

This directory contains ArgoCD `Application` manifests for teams already running Argo CD who want to manage their RHOAI install via GitOps.

> **The manual install path (numbered directories + `oc apply -f`) is the primary path.** These ArgoCD manifests are an optional convenience layer that uses the exact same YAML files — no duplication.

## How It Works

Each Application points `path:` at one of the numbered directories in this repo. ArgoCD syncs the same YAML that you would apply manually:

```
gitops/rhoai-required-deps.yaml      → sources: 01-required-dependencies/*/
gitops/rhoai-optional-deps.yaml      → sources: 02-optional-dependencies/*/
gitops/rhoai-operator.yaml           → path: 03-rhoai-operator/
gitops/rhoai-datasciencecluster.yaml → path: 04-datasciencecluster/
```

Sync waves enforce install order:

| Application | Wave | Contents |
|---|---|---|
| `rhoai-required-deps` | 0 | All 6 required dependency operators |
| `rhoai-optional-deps` | 0 | Optional operators (edit sources for your environment) |
| `rhoai-operator` | 1 | RHOAI operator subscription |
| `rhoai-datasciencecluster` | 2 | DataScienceCluster CR |

## Prerequisites

- OpenShift GitOps (Argo CD) installed and running in `openshift-gitops`
- Argo CD service account has `cluster-admin` or equivalent (needed to create namespaces and cluster-scoped resources)
- This repo forked and pushed to your Git server

## Setup

**1. Fork this repo** and update `repoURL` in all Application manifests:

```bash
# Replace placeholder in all gitops/ files
sed -i 's|https://github.com/YOUR-ORG/rhoai-install.git|https://github.com/<your-org>/rhoai-install.git|g' gitops/*.yaml
```

**2. Edit optional deps** — open `gitops/rhoai-optional-deps.yaml` and remove the `sources` entries for operators you are not installing.

**3. Edit the DataScienceCluster** — open `04-datasciencecluster/datasciencecluster.yaml` and set `managementState` values for your environment. Commit and push.

**4. Apply the Applications** (in order, or all at once — sync waves handle sequencing):

```bash
# Apply all at once — Argo CD will sequence via sync waves
oc apply -f gitops/rhoai-required-deps.yaml
oc apply -f gitops/rhoai-optional-deps.yaml
oc apply -f gitops/rhoai-operator.yaml
oc apply -f gitops/rhoai-datasciencecluster.yaml
```

**5. Monitor sync status:**

```bash
oc get applications -n openshift-gitops
# Or via the Argo CD UI: https://openshift-gitops-server-openshift-gitops.apps.<cluster-domain>
```

## Limitations

- **Job Set CR ordering:** ArgoCD applies all files in `01-required-dependencies/job-set/` simultaneously, including `jobsetoperator-cr.yaml`. The CR may fail initially if the CSV hasn't reached `Succeeded` yet — ArgoCD's `selfHeal: true` will retry and it will eventually succeed.
- **NFD → GPU ordering:** Both NFD and GPU operator are in the same wave-0 Application. The ClusterPolicy CR may fail until NFD labels the nodes. Self-heal retries resolve this. If strict ordering is required, split them into separate Applications at waves 0 and 1.
- **DSC `ignoreDifferences`:** The DSC Application ignores `/spec` drift by default, so RHOAI dashboard changes to components won't be reverted. Remove the `ignoreDifferences` block for strict GitOps.
