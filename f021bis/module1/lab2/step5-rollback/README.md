# Step 5 — rollback, and its limits

**Slide:** Upgrading a component: the order · **~10 min**

## Roll the control plane back

```sh
helm history linkerd-control-plane -n linkerd
helm rollback linkerd-control-plane 1 -n linkerd --wait
helm history linkerd-control-plane -n linkerd        # a NEW revision, "Rollback to 1"
linkerd check --proxy -n bookinfo
```

Now the proxies (rolled in step 4) are **newer** than the control plane,
and so is the CLI: the *versions match* lines say so. Nothing breaks today;
the support window between them is the release notes' business, not
Helm's.

## And the CRDs?

```sh
kubectl get crd httproutes.policy.linkerd.io \
  -o jsonpath='{range .spec.versions[*]}{.name} served={.served} storage={.storage}{"\n"}{end}'
kubectl get crd httproutes.policy.linkerd.io -o jsonpath='{.status.storedVersions}'; echo
```

`linkerd-crds` *templates* its CRDs, so Helm would roll them back like any
other object — it does not hold CRDs special, only the files in a chart's
`crds/` directory (installed once, never upgraded, never deleted). What
protects stored objects is the API server: it refuses a CRD that drops a
version still listed in `status.storedVersions`. Fields the old schema does
not know are pruned from objects when they are read.

## Back to the end state

```sh
helm upgrade linkerd-control-plane linkerd-edge/linkerd-control-plane \
  -n linkerd --version "$LINKERD_TO" \
  -f lab2/values/control-plane.yaml \
  --set-file identityTrustAnchorsPEM=lab2/certs/ca.crt \
  --set-file identity.issuer.tls.crtPEM=lab2/certs/issuer.crt \
  --set-file identity.issuer.tls.keyPEM=lab2/certs/issuer.key \
  --wait --timeout 10m
linkerd check --proxy -n bookinfo
```

## Questions

- A rollback is a new revision. What does that mean for `helm history` as
  an audit trail?
- The new version added a field to a CRD and you created objects using it.
  What happens to that field after a rollback of the CRD chart?
- So what is the real safety net for a component upgrade? (A rehearsal on a
  copy of production — not `helm rollback`.)
