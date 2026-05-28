# Phase 0: Cluster Pre-Validation

Run these checks before installing any operators. All checks must pass before proceeding to Phase 1.

**Requirements:** `oc` CLI, logged in as a non-`kubeadmin` cluster-admin user.

## Fast Path — Automated Check

From the repo root:

```bash
bash guides/rhoai-prerequisites-check.sh
```

The script exits `0` when all hard checks pass, or non-zero equal to the number of `✗ FAIL` items.

Output legend: `✓ OK` = passed · `✗ FAIL` = blocking · `⚠ WARN` = non-blocking · `ℹ VERIFY` = manual check needed

## Checklist

| Check | Pass Criteria | Required |
|---|---|---|
| OCP version | 4.19 or 4.20 (4.20 required for llm-d) | **Required** |
| Worker nodes | 2+ nodes × 8 CPU + 32 GiB RAM (SNO: 32 CPU + 128 GiB) | **Required** |
| Default StorageClass | Marked `(default)`, dynamic provisioning | **Required** |
| Identity Provider | At least one IdP (htpasswd, LDAP, OIDC, etc.) — not just kubeadmin | **Required** |
| cluster-admin user | Non-`kubeadmin` user with `cluster-admin` role | **Required** |
| Open Data Hub | NOT installed | **Required** |
| Network (from nodes) | `registry.redhat.io`, `quay.io`, `cdn.redhat.com` reachable from worker nodes | **Required** |
| RHOAI subscription | Valid Red Hat OpenShift AI Self-Managed entitlement | **Required** |

## Optional prerequisites (by component)

These are not blocking for install — plan them before enabling the matching DataScienceCluster components:

| If you enable… | Also need… |
|---|---|
| `aipipelines` | S3-compatible object storage |
| `modelregistry` | MySQL 5.x+ (8.x recommended) and S3 |
| `mlflowoperator` (production) | External DB and S3 |
| GPU / llm-d workloads | GPU nodes and optional dependency operators (NFD, GPU operator, LWS, etc.) |
| `llamastackoperator` | Service Mesh 3.x, cert-manager, GPU, and NFD |

Model serving (`kserve`) does not require object storage — models can use PVC, OCI, S3, or inline sources.

## Manual Commands

```bash
# OCP version (must be 4.19–4.20)
oc version

# Worker nodes — 2+ workers × 8 CPU + 32 GiB
oc get nodes -o wide
oc describe nodes | grep -A3 "Capacity:"

# Default StorageClass
oc get storageclass

# Identity provider
oc get oauth cluster -o jsonpath='{.spec.identityProviders}' | python3 -m json.tool

# Open Data Hub — must be absent
oc get subscription -A | grep -i opendatahub || echo "ODH not found — OK"

# Network from a cluster node (not your laptop — image pulls happen on nodes)
NODE=$(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[0].metadata.name}')
oc debug node/$NODE -- chroot /host curl -s -o /dev/null -w "%{http_code}\n" https://registry.redhat.io/v2/
oc debug node/$NODE -- chroot /host curl -s -o /dev/null -w "%{http_code}\n" https://quay.io/v2/
oc debug node/$NODE -- chroot /host curl -s -o /dev/null -w "%{http_code}\n" https://cdn.redhat.com
# Expected: any HTTP status (200, 301, 401, 403) = reachable
# Bad: curl exit 6 or 7 = not reachable
```

## Next Step

Once all checks pass, proceed to [Phase 1: Required Dependencies](../01-required-dependencies/README.md).
