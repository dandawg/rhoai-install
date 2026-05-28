# Phase 4 & 5: Configuration and Validation

This directory contains post-install configuration resources for RHOAI components.
Apply only what is relevant to your environment.

## Phase 4: User Access (Optional)

By default, all OpenShift users can access RHOAI. Skip this section if that is acceptable.

```bash
# Create user groups
oc apply -f 05-configuration/user-access/groups.yaml

# Add users to groups
oc adm groups add-users rhods-users <username>
oc adm groups add-users rhods-admins <admin-username>

# Then configure RHOAI to use these groups:
# RHOAI Dashboard → Settings → User management
```

See [User management docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/managing_openshift_ai/managing-users-and-groups#adding-users-to-user-groups_managing-rhoai).

## Phase 5: Dashboard Access and Final Validation

```bash
# Get the dashboard URL
oc get route -n redhat-ods-applications | grep rhods-dashboard
```

> Starting with RHOAI 3.4, the dashboard URL format is `https://rh-ai.apps.<cluster-domain>`.

**Final validation checklist:**

| Check | Command / Action | Expected |
|---|---|---|
| Dashboard loads | Open URL in browser | Login page, login succeeds |
| Components visible | Dashboard → Help → About | Enabled components listed |
| DSC Ready | `oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}'` | `Ready` |
| Pods healthy | `oc get pods -n redhat-ods-applications` | No CrashLoopBackOff or Error |
| GPU detected | `oc describe node <gpu-node> \| grep nvidia.com/gpu` | GPU in Capacity and Allocatable |
| Non-admin login | Log in as a data scientist user | Dashboard visible |

---

## Distributed Workloads: Configure Kueue Queues

After installing the Kueue operator and enabling `kueue: Unmanaged` in the DSC:

```bash
# Create the ClusterQueue (edit quotas first to match your cluster)
oc apply -f 05-configuration/distributed-workloads/clusterqueue.yaml

# Create a LocalQueue in each project namespace where workloads will run
oc apply -f 05-configuration/distributed-workloads/localqueue.yaml -n <project-namespace>
```

See [Distributed workloads docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/managing_openshift_ai/managing-distributed-workloads_managing-rhoai).

---

## Distributed Inference (llm-d): Configure Gateway

After installing LWS and RHCL operators, and with kserve enabled in the DSC:

```bash
# Create GatewayClass (once per cluster)
oc apply -f 05-configuration/llm-d/gateway-class.yaml

# Create the shared Gateway
oc apply -f 05-configuration/llm-d/gateway.yaml
```

Requirements: OCP 4.20+, kserve Managed, LWS operator, RHCL operator. Service Mesh v2 must NOT be installed.

See [llm-d Distributed Inference docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/deploy_models_using_distributed_inference_with_llm-d/deploying-models-using-distributed-inference_distributed-inference#enabling-distributed-inference_distributed-inference).

---

## Hardware Profiles (kserve)

Create hardware profiles to let data scientists select GPU resources when deploying models.

**GUI:** RHOAI Dashboard → Settings → Environment setup → Hardware profiles → Add hardware profile

See [Hardware profiles docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_accelerators/working-with-hardware-profiles_accelerators).

---

## AI Pipelines: Configure Object Storage

AI pipelines require S3-compatible object storage.

**GUI:** RHOAI Dashboard → Data Science Projects → [project] → Connections → Add connection → S3-compatible object storage

Then: Data Science Projects → [project] → Pipelines → Configure pipeline server

See [AI Pipelines docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_ai_pipelines).

---

## Certificates: Add Custom CA Bundle

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
