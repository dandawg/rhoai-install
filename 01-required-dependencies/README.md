# Phase 1: Required Dependencies

Install all six operators below before installing the RHOAI operator. These are required for every RHOAI 3.x deployment.

> Some operators require creating a CR instance after install — marked with **Create CR** below. The operator is non-functional until this step is complete even though the subscription shows `Succeeded`.

After completing all installs and CR steps, run the dependency check from the repo root:

```bash
bash guides/rhoai-dependency-check.sh
```

---

> **⚠ If any of these operators are already installed on your cluster**, run the dependency check first to see what is already present:
>
> ```bash
> bash guides/rhoai-dependency-check.sh
> ```
>
> For any operator shown as `✓ READY`, **skip its `oc apply -f` block entirely** (or apply only the specific files that are missing). Applying an `operatorgroup.yaml` to a namespace that already has an OperatorGroup creates a duplicate, which causes OLM to fail the CSV with `TooManyOperatorGroups`.
>
> **Recovery if you already hit `TooManyOperatorGroups`:**
> 1. Identify the duplicate: `oc get operatorgroup -n <namespace>`
> 2. Delete the newer/duplicate one: `oc delete operatorgroup <duplicate-name> -n <namespace>`
> 3. Delete the failed CSV: `oc delete csv <csv-name> -n <namespace>`
> 4. Bounce the subscription to get a fresh InstallPlan:
>    ```bash
>    oc delete subscription <sub-name> -n <namespace>
>    oc apply -f 01-required-dependencies/<dir>/subscription.yaml
>    ```

---

## 1. cert-manager Operator

| | |
|---|---|
| Package | `openshift-cert-manager-operator` |
| Namespace | `cert-manager-operator` |
| Channel | `stable-v1` |
| CR required? | No — pods start automatically |

```bash
oc apply -f 01-required-dependencies/cert-manager/
```

> **⚠ cert-manager is commonly pre-installed.** Check before applying:
> ```bash
> oc get csv -n cert-manager-operator
> ```
> If the CSV shows `Succeeded`, the operator is healthy — skip the `oc apply -f` above. Applying it anyway will create a second OperatorGroup and break the install (see recovery note at the top of this page).

**Verify:**

```bash
oc get pods -n cert-manager
# Expected: 3 pods Running (cert-manager, cainjector, webhook)
```

---

## 2. Job Set Operator

| | |
|---|---|
| Package | `job-set` |
| Namespace | `openshift-jobset-operator` |
| Channel | `stable-v1.0` |
| CR required? | **Yes** — `JobSetOperator` CR named `cluster` |

```bash
oc apply -f 01-required-dependencies/job-set/namespace.yaml
oc apply -f 01-required-dependencies/job-set/operatorgroup.yaml
oc apply -f 01-required-dependencies/job-set/subscription.yaml
```

Wait for the CSV to reach `Succeeded`:

```bash
oc get csv -n openshift-jobset-operator -w
```

**Create CR** (operator does not function until this is applied):

```bash
oc apply -f 01-required-dependencies/job-set/jobsetoperator-cr.yaml
```

**Verify:**

```bash
oc get JobSetOperator cluster
oc get pods -n openshift-jobset-operator
```

---

## 3. Custom Metrics Autoscaler (KEDA)

| | |
|---|---|
| Package | `openshift-custom-metrics-autoscaler-operator` |
| Namespace | `openshift-keda` |
| Channel | `stable` |
| CR required? | No — `KedaController` CR is auto-created (v2.17.2+) |

```bash
oc apply -f 01-required-dependencies/custom-metrics-autoscaler/
```

**Verify:**

```bash
oc get pods -n openshift-keda
oc get KedaController -n openshift-keda
```

---

## 4. Red Hat build of OpenTelemetry

| | |
|---|---|
| Package | `opentelemetry-product` |
| Namespace | `openshift-opentelemetry-operator` |
| Channel | `stable` |
| CR required? | No — RHOAI creates collector instances via DSCI when observability is enabled |

```bash
oc apply -f 01-required-dependencies/opentelemetry/
```

**Verify:**

```bash
oc get pods -n openshift-opentelemetry-operator
```

> **Note:** Required per the [official install guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/installing_and_uninstalling_openshift_ai_self-managed) when DSCI observability features are enabled. Install it unless you are certain observability will not be used.

---

## 5. Tempo Operator

| | |
|---|---|
| Package | `tempo-product` |
| Namespace | `openshift-tempo-operator` |
| Channel | `stable` |
| CR required? | No — RHOAI creates Tempo instances via DSCI when observability is enabled |

```bash
oc apply -f 01-required-dependencies/tempo/
```

**Verify:**

```bash
oc get pods -n openshift-tempo-operator
```

> **Note:** Required when DSCI observability features are enabled (same as OpenTelemetry above).

---

## 6. Cluster Observability Operator

| | |
|---|---|
| Package | `cluster-observability-operator` |
| Namespace | `openshift-cluster-observability-operator` |
| Channel | `stable` |
| CR required? | No — RHOAI manages observability resources via DSCI |

```bash
oc apply -f 01-required-dependencies/cluster-observability/
```

**Verify:**

```bash
oc get pods -n openshift-cluster-observability-operator
```

> **Note:** Required when DSCI observability features are enabled (same as OpenTelemetry above).

---

## Validate All Required Dependencies

```bash
bash guides/rhoai-dependency-check.sh
```

All six required operators must show `✓ READY` before proceeding.

**Manual CSV check:**

```bash
# Check all required subscriptions at once
oc get subscription -A | grep -iE "cert-manager|job-set|custom-metrics-autoscaler|opentelemetry-product|tempo-product|cluster-observability"

# Verify specific operator CSV
SUB=<sub-name>; NS=<namespace>
CSV=$(oc get subscription $SUB -n $NS -o jsonpath='{.status.installedCSV}')
oc get csv $CSV -n $NS -o jsonpath='{.status.phase}{"\n"}'  # expect: Succeeded
```

---

## Next Step

Once all operators show `✓ READY`, review the optional dependencies in [Phase 1b: Optional Dependencies](../02-optional-dependencies/README.md), then proceed to [Phase 2: RHOAI Operator](../03-rhoai-operator/README.md).
