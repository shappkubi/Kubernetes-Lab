Two sharpenings
Q1 — Ownership chain. Your answer skipped the actual chain. Try this in your head:

"Deployment is what I create. The Deployment controller creates a ReplicaSet for each unique pod spec hash. The ReplicaSet controller creates Pods. Each child has an ownerReferences field pointing back up. When I kubectl delete deploy/web, K8s walks the chain via ownerReferences and garbage-collects the ReplicaSets and Pods automatically."

The key word is ReplicaSet. The Deployment doesn't create pods directly — it creates RS, RS creates pods. That layer is what makes rolling updates and rollbacks work.
Q2 — what maxSurge actually controls.  It controls how many extra pods can exist during a rollout while old pods haven't been killed yet:

maxSurge: 1 → during a rollout the cluster can briefly have 6 pods total (5 desired + 1 surge) so the new RS can scale up while the old one scales down.
maxUnavailable: 1 → at least 4 pods must be Ready during the rollout, so traffic keeps flowing.

It's about the rollout transition, not steady-state traffic.

Q3 — Why keep old ReplicaSets at READY 0? Think back to what kubectl rollout undo did for you in 30 seconds.

Hint: the old ReplicaSet's pod template (with the previous image, env, resources, everything) is preserved. Rollback isn't "go fetch the old version" — it's "scale this RS up, scale that RS down." The image is already cached on nodes. That's why rollback is fast.

Q5 — what did a stuck rollout look like? You watched it. Six pods, four ready, two stuck in ImagePullBackOff. Customers saw nothing wrong. The thing that saved you was maxUnavailable: 1 — the Deployment refused to kill more healthy pods.