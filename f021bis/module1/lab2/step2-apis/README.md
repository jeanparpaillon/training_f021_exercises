# Step 2 — API versions and a legacy manifest

**Slides:** The Kubernetes API is versioned · CRDs · **~15 min**

## What this cluster serves

```sh
kubectl api-resources | head -20
kubectl api-versions | grep -E 'policy|batch|discovery'
kubectl get --raw /apis/policy | jq '.versions'
kubectl explain pdb.spec --recursive | head -20
kubectl get --raw /openapi/v3 | jq -r '.paths | keys[]' | head
```

## A manifest from three years ago

Read [`legacy.yaml`](legacy.yaml), predict, then:

```sh
kubectl apply -f lab2/step2-apis/legacy.yaml
```

Two different fates: the `policy/v1beta1` PodDisruptionBudget is refused
(`no matches for kind`, removed in 1.25); the `v1` Endpoints is accepted with
a warning (deprecated in 1.33). Who else has used a deprecated API since the
API server started?

```sh
kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis
```

## CRDs have versions too

```sh
kubectl get crd | grep gateway                     # none yet: step 3 adds them
kubectl get crd -o custom-columns=NAME:.metadata.name,VERSIONS:.spec.versions[*].name,STORED:.status.storedVersions
```

## Clean up

```sh
kubectl delete -f lab2/step2-apis/legacy.yaml --ignore-not-found
```

## Questions

- The refused PDB's error ends with *"ensure CRDs are installed first"*.
  Why would kubectl suggest that for a built-in type?
- A warning scrolls past in a CI log. How would you make your pipeline fail
  on it? (`kubectl apply --warnings-as-errors`.)
- Who decides the version an object is *stored* in, and how are stored
  objects moved before a version is removed?
