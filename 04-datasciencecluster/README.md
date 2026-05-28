# Phase 3: Configure the DataScienceCluster

Create the `DataScienceCluster` CR to install and enable RHOAI components. The RHOAI operator must be installed and its CSV in `Succeeded` state before applying this.

## Choose a Configuration

| File | Description |
|---|---|
| `datasciencecluster.yaml` | **Default** — core + common optional components; edit `managementState` for your environment |
| `variants/datasciencecluster-minimal.yaml` | Minimal — dashboard, workbenches, kserve, aipipelines only |
| `variants/datasciencecluster-gpu-kueue.yaml` | Full — adds Kueue (Unmanaged), Ray, Trainer, distributed workloads |

## Apply

```bash
# Default configuration (edit first to match your environment):
oc apply -f 04-datasciencecluster/datasciencecluster.yaml

# Or a variant:
oc apply -f 04-datasciencecluster/variants/datasciencecluster-minimal.yaml
```

## Component Reference

| Component | managementState | Prerequisites | Notes |
|---|---|---|---|
| `dashboard` | **Managed** | None | Always enable |
| `workbenches` | **Managed** | Default StorageClass | JupyterLab, VS Code, RStudio |
| `aipipelines` | **Managed** | S3 storage | Kubeflow Pipelines |
| `kserve` | **Managed** | cert-manager | Single-model serving, vLLM, LLMs |
| `kueue` | **Unmanaged** if Kueue operator installed, else **Removed** | Red Hat Kueue Operator | Job queuing for distributed workloads |
| `ray` | Managed / Removed | Kueue + cert-manager | Ray distributed compute |
| `trainer` | Managed / Removed | Job Set operator | Kubeflow Trainer v2 |
| `trainingoperator` | Removed (legacy) | Kueue + cert-manager | Legacy Kubeflow Training Operator |
| `modelregistry` | Managed / Removed | MySQL 5.x+ (prod) | Centralized model metadata |
| `trustyai` | Managed / Removed | None | Model monitoring, explainability |
| `llamastackoperator` | Managed / Removed | Service Mesh 3.x + cert-manager + GPU + NFD | Llama Stack for RAG/GenAI |
| `mlflowoperator` | Managed / Removed | PVC (dev) or DB + S3 (prod) | MLflow experiment tracking |
| `feastoperator` | Managed / Removed | None | Feast Feature Store |
| `sparkoperator` | Removed | Custom Spark image | Apache Spark 4.x |

## Verify

```bash
# Watch components become ready (may take 5-10 minutes)
oc get datasciencecluster default-dsc -w

# Check phase (expect: Ready)
oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}{"\n"}'

# Check component pods
oc get pods -n redhat-ods-applications
```

Validation checklist:

| Check | Command | Expected |
|---|---|---|
| DSC phase | `oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}'` | `Ready` |
| Component pods | `oc get pods -n redhat-ods-applications` | All Running or Completed |
| Dashboard route | `oc get route -n redhat-ods-applications \| grep rhods-dashboard` | Route URL present |
| RHOAI version | `oc get datasciencecluster default-dsc -o jsonpath='{.status.release.version}'` | `3.4.x` |

## Modifying Components After Initial Install

Components can be enabled or disabled at any time by patching the DSC:

```bash
# Enable a component (example: mlflowoperator)
oc patch datasciencecluster default-dsc \
  --type=merge \
  -p '{"spec":{"components":{"mlflowoperator":{"managementState":"Managed"}}}}'

# Disable a component
oc patch datasciencecluster default-dsc \
  --type=merge \
  -p '{"spec":{"components":{"mlflowoperator":{"managementState":"Removed"}}}}'
```

## Next Step

Proceed to [Phase 4/5: Configuration](../05-configuration/README.md) to configure user access, hardware profiles, distributed workloads, and other post-install settings.
