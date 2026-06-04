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

After installing LWS operator, and with kserve enabled in the DSC:

```bash
# Step 1: Create the Kuadrant namespace and CR (RHCL operator required — for auth only)
oc create namespace kuadrant-system --dry-run=client -o yaml | oc apply -f -
oc apply -f 05-configuration/llm-d/kuadrant-cr.yaml
oc wait Kuadrant kuadrant -n kuadrant-system --for=condition=Ready --timeout=10m

# Step 2: Create GatewayClass (once per cluster — uses OCP Ingress Operator, NOT Kuadrant)
oc apply -f 05-configuration/llm-d/gateway-class.yaml

# Step 3: Create the shared Gateway
oc apply -f 05-configuration/llm-d/gateway.yaml
```

Requirements: OCP 4.19.9+ (4.20+ for full llm-d), kserve Managed, LWS operator. RHCL operator required only for auth policy enforcement (Kuadrant). Service Mesh v2 must NOT be installed.

> **GatewayClass controller:** Uses `openshift.io/gateway-controller/v1` (OCP Ingress Operator / Istio). Do NOT use `gateway.envoyproxy.io/gatewayclass-controller` — that is for the standalone Red Hat AI Inference product.

See [llm-d Distributed Inference docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/deploy_models_using_distributed_inference_with_llm-d/deploying-models-using-distributed-inference_distributed-inference#enabling-distributed-inference_distributed-inference).

---

## Llama Stack

After enabling `llamastackoperator: Managed` in the DSC, there are two distinct use cases:

### A — AI Playground (auto-managed, no manual CR)

The gen-ai-studio AI Playground **auto-creates** a `LlamaStackDistribution` named `lsd-genai-playground` when a user creates a playground instance. Admins do not create this manually.

User flow: Gen AI studio → AI asset endpoints → **Add to playground** → `lsd-genai-playground` is created automatically.

**Prerequisite:** The InferenceService must have label `opendatahub.io/genai-asset: "true"` (set via "Add as AI asset endpoint" checkbox in the dashboard).

See [Playground prerequisites](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/experimenting_with_models_in_the_gen_ai_playground/playground-prerequisites_rhoai-user).

### B — RAG / Agentic Apps (manual CR required)

For programmatic Llama Stack API access (RAG pipelines, SDK-based agentic workflows), create a `LlamaStackDistribution` manually. **PostgreSQL is required** for all metadata backends.

```bash
# Customize all <placeholder> values first, then apply
oc apply -f 05-configuration/llama-stack/llamastackdistribution-example.yaml
```

See [Deploying a Llama Stack server](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_llama_stack/deploying-llama-stack-server_rag).

---

## MLflow: Create an MLflow Tracking Server

After enabling `mlflowoperator: Managed` in the DSC:

```bash
# Dev/test (SQLite + PVC):
oc apply -f 05-configuration/mlflow/mlflow-cr.yaml

# Edit mlflow-cr.yaml first for production (PostgreSQL + S3)
```

See [Working with MLflow](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_mlflow).

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
