# Step 6 — fallback

**Slide:** Lab 1 — fallback · **~5 min + 15 min debrief**

Nothing to apply. The overlay is the end state of lab 1, and lab 2 starts
from it:

```sh
kubectl -n "$NS" apply -k lab1/step6-fallback
```

## Lose a dependency, keep the page

```sh
kubectl -n "$NS" scale deploy/ratings-v1 --replicas=0
```

Reload the page a few times, or count from the toolbox:

```sh
kubectl -n "$NS" exec deploy/toolbox -- sh -c 'for i in $(seq 1 6); do
  wget -qO- http://productpage:9080/productpage \
    | grep -o "Ratings service is currently unavailable\|reviews-v[0-9]" | sort -u | tr "\n" " "; echo; done'
```

The page still renders. With `reviews` v2 and v3 it shows *"Ratings service
is currently unavailable"* instead of the stars. With v1 nothing is
missing, because v1 never calls `ratings`.

Do the same with `details`:

```sh
kubectl -n "$NS" scale deploy/ratings-v1 --replicas=1
kubectl -n "$NS" scale deploy/details-v1 --replicas=0
# reload: "Sorry, product details are currently unavailable for this book."
kubectl -n "$NS" scale deploy/details-v1 --replicas=1
```

## Find the fallback in the code

Nobody configured this. It is written in the application:

- `productpage`: `getProductDetails` and `getProductReviews` in
  `productpage.py` catch the failure and return an error message, which the
  template renders in place of the section:

  ```sh
  kubectl -n "$NS" exec deploy/productpage-v1 -c productpage -- \
    grep -n "currently unavailable" productpage.py
  ```

- `reviews`: the Java service catches the failed call to `ratings` and puts
  `{"error": "Ratings service is currently unavailable"}` in place of each
  rating. It is in `LibertyRestEndpoint.java` in the upstream sources
  ([istio/istio, `samples/bookinfo/src/reviews`](https://github.com/istio/istio/tree/master/samples/bookinfo/src/reviews)),
  and you can see the result directly:

  ```sh
  kubectl -n "$NS" scale deploy/ratings-v1 --replicas=0
  kubectl -n "$NS" exec deploy/toolbox -- wget -qO- http://reviews:9080/reviews/0
  kubectl -n "$NS" scale deploy/ratings-v1 --replicas=1
  ```

## Questions

- The page survives without `ratings` and without `details`, but not
  without `reviews`: without reviews the whole reviews section is gone.
  Who made that decision, where is it written down, and should it have been
  a developer alone?
- The k6 summary counted every one of these pages as a successful request.
  What would you alert on instead?

## Debrief (15 min)

Go back to your table of numbers, step by step.

- Which of today's fixes were **pure manifests** (probes, preStop, spread,
  PDB), and which **needed code** (timeouts, SIGTERM handling, fallback)?
  Place each one in the "where to implement" grid from the slides.
- Which changes did the platform team make alone, and which needed the
  application team?
- What is still unprotected? The slow dependency of step 5 still costs
  seconds per request, and fixing it means a code change in two languages.
  That is where lab 2 starts.

Before moving on, check that no fault is left behind:

```sh
kubectl -n "$NS" get deploy ratings-blackhole 2>/dev/null && \
  kubectl -n "$NS" delete -f faults/ratings-blackhole.yaml
kubectl -n "$NS" apply -k lab1/step6-fallback
```
