# Phase 2: Install the RHOAI Operator

Install the Red Hat OpenShift AI operator. All Phase 1 required dependencies must be installed and healthy before proceeding.

## Install via CLI

```bash
oc apply -f 03-rhoai-operator/
```

This applies three resources in order: Namespace, OperatorGroup, Subscription.

> If applying individually (e.g., to control ordering):
> ```bash
> oc apply -f 03-rhoai-operator/namespace.yaml
> oc apply -f 03-rhoai-operator/operatorgroup.yaml
> oc apply -f 03-rhoai-operator/subscription.yaml
> ```

## Install via Web Console

Operators → OperatorHub → search **"Red Hat OpenShift AI"** → Install

- Installation mode: All namespaces
- Installed namespace: `redhat-ods-operator`
- Update channel: `stable-3.x`

> When using the web console, OperatorHub creates the namespace and OperatorGroup automatically — the CLI files 03-rhoai-operator/ are not needed.

## Verify

Watch the CSV reach `Succeeded` (usually takes 2–5 minutes):

```bash
oc get csv -n redhat-ods-operator -w
```

Confirm the operator is running:

```bash
oc get pods -n redhat-ods-operator
# Expected: rhods-operator pod Running
```

Check the installed CSV version:

```bash
oc get csv -n redhat-ods-operator -o jsonpath='{.items[0].spec.version}{"\n"}'
# Expected: 3.4.x
```

## Channel Reference

| Channel | Use Case |
|---|---|
| `stable-3.x` | Latest stable patch within the 3.x release train |
| `stable-3.4` | Pinned to 3.4, manual upgrades to 3.5+ |
| `fast-3.x` | Latest including pre-release patches |
| `stable` | Follows the latest stable release train |

See [RHOAI update channels](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/installing_and_uninstalling_openshift_ai_self-managed/understanding-update-channels_install) for full details.

## Next Step

Once the CSV shows `Succeeded`, proceed to [Phase 3: Configure the DataScienceCluster](../04-datasciencecluster/README.md).
