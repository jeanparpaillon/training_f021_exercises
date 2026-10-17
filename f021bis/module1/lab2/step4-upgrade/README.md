# Step 4 — upgrade Linkerd, in order

**Slide:** Upgrading a component: the order · **~20 min**

`LINKERD_FROM` → `LINKERD_TO`: CRDs, control plane, viz, data plane, CLI.

## Read before you touch

Release notes for every version between the two:
<https://github.com/linkerd/linkerd2/releases>. Then the actual change, for
each release — what is running vs what the new chart would render:

```sh
helm get manifest linkerd-crds -n linkerd > /tmp/crds-before.yaml
helm template linkerd-crds linkerd-edge/linkerd-crds -n linkerd \
  --version "$LINKERD_TO" > /tmp/crds-after.yaml
diff /tmp/crds-before.yaml /tmp/crds-after.yaml | less
```

Same for the control plane — with the **same values and certificates**, or
the diff is noise:

```sh
helm get manifest linkerd-control-plane -n linkerd > /tmp/cp-before.yaml
helm template linkerd-control-plane linkerd-edge/linkerd-control-plane -n linkerd \
  --version "$LINKERD_TO" -f lab2/values/control-plane.yaml \
  --set-file identityTrustAnchorsPEM=lab2/certs/ca.crt \
  --set-file identity.issuer.tls.crtPEM=lab2/certs/issuer.crt \
  --set-file identity.issuer.tls.keyPEM=lab2/certs/issuer.key > /tmp/cp-after.yaml
diff /tmp/cp-before.yaml /tmp/cp-after.yaml | grep '^[<>]' | grep -v -i checksum | less
```

## 1. CRDs

```sh
helm upgrade linkerd-crds linkerd-edge/linkerd-crds -n linkerd --version "$LINKERD_TO"
```

## 2. Control plane

Every flag of the install again: values file, certificates. Never
`--reuse-values`.

```sh
helm upgrade linkerd-control-plane linkerd-edge/linkerd-control-plane \
  -n linkerd --version "$LINKERD_TO" \
  -f lab2/values/control-plane.yaml \
  --set-file identityTrustAnchorsPEM=lab2/certs/ca.crt \
  --set-file identity.issuer.tls.crtPEM=lab2/certs/issuer.crt \
  --set-file identity.issuer.tls.keyPEM=lab2/certs/issuer.key \
  --wait --timeout 10m --rollback-on-failure
helm upgrade linkerd-viz linkerd-edge/linkerd-viz \
  -n linkerd-viz --version "$LINKERD_TO" -f lab2/values/viz.yaml --wait --timeout 10m
helm history linkerd-control-plane -n linkerd
```

## 3. Data plane

```sh
linkerd check --proxy -n bookinfo
```

Read the *versions match* lines: the control plane runs the new version,
the Bookinfo proxies the old one. Proxies are injected at pod creation and
never change in place. Roll them, deliberately:

```sh
kubectl -n bookinfo rollout restart deploy
kubectl -n bookinfo rollout status deploy --timeout=5m
```

## 4. Clients

```sh
make -C lab0 linkerd-to
linkerd version
linkerd check --proxy -n bookinfo
```

## Questions

- Why CRDs before the control plane, and never the other way round?
- Between step 2 and step 3, old proxies talked to a new control plane. Who
  guarantees that works, and for how many versions apart?
- What does `--rollback-on-failure` do, and what would it *not* undo?
