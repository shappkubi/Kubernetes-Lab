Day 2 — what you actually did
Three experiments, one mental model
2.1 — restartPolicy & CrashLoopBackOff. You created a pod that exited 1 every 5 seconds and observed two different behaviors:

With restartPolicy: Never, the pod went to Failed once and stayed dead.
With restartPolicy: OnFailure, the kubelet kept restarting it. You watched the RESTARTS counter climb and the STATUS alternate between Running and CrashLoopBackOff. The backoff between restarts was 10s, then ~12s, growing each cycle.

You also learned that restartPolicy is immutable on a Pod — kubectl apply returns "unchanged" because the field can't be edited live. You have to kubectl delete and re-apply to change it.
The artifact in your head: when a container exits, look at kubectl describe pod → Last State → Reason + Exit Code. That's where every CrashLoopBackOff investigation starts.

2.2 — Init containers. You created a pod with one init container that slept 10 seconds before nginx started. You saw:

Status moved through Init:0/1 → Init:1/1 → PodInitializing → Running.
In kubectl describe, the init container had its own section with State: Terminated, Reason: Completed, Exit Code: 0.
The events timeline showed an 11-second gap between the init container starting and the main container beginning to pull its image — physical proof that init blocks startup.
Init container logs persisted (kubectl logs <pod> -c <init-name>) even after the container exited.

The artifact in your head: init containers run sequentially to completion, before main containers, share the pod's volumes, and each must exit 0 before the next starts. Used for migrations, dependency waiting, secret bootstrapping.

2.3 — Sidecar pattern (multi-container pod). You created a pod with two containers — writer (appended dates to /var/log/app.log) and log-shipper (tail -F on the same file). You observed:

READY showed 2/2 — two containers, both alive.
kubectl logs <pod> -c log-shipper -f streamed dates the writer was producing in real time. Two containers, sharing nothing in the app code, talking via a file in a shared emptyDir volume.
kubectl exec -it <pod> -c writer -- sh showed hostname was the pod name — confirming both containers share the network namespace.
A nuance: the cluster sandbox restarted mid-lab, both containers got Restart Count: 1, but the emptyDir file persisted with both eras of date lines visible. emptyDir is tied to the pod, not each container.

The artifact in your head: a pod = shared network namespace + shared volumes + N containers. Sidecars are how you add cross-cutting concerns (logging, mesh proxy, secrets rotation) without touching the app.

Commands you ran enough times to have memorized
CommandWhen you reach for itkubectl apply -f <file>Create/update from YAMLkubectl get pod <name> -wWatch lifecycle in real timekubectl describe pod <name>The detailed truth: state, events, conditionskubectl logs <pod> -c <container>Read a specific container's stdoutkubectl logs <pod> -c <container> -fStream those logs livekubectl exec -it <pod> -c <container> -- shDrop into a containerkubectl delete pod <name>Tear down
The Lab 2 elevator pitch

"A pod is the smallest deployable unit in K8s — one or more containers sharing a network namespace and optionally volumes. Containers in a pod live and die together. restartPolicy controls what happens when a container exits; CrashLoopBackOff is the kubelet's exponential-backoff state between restart attempts. Init containers run setup work to completion before the main container starts. Sidecars run alongside the main container to handle cross-cutting concerns. emptyDir volumes are ephemeral with the pod, not the container."

----------------------------
in my own words
----------------------------
from what i learnt for Day2, first Restartpolicy and CrashLoopBackOff is a common debuging situation. when restartPolicy is set at Never, it iplies that when a pod goes to a failed state remains dead. on the other hand  restartpolicy set to OnFailure means , when it fails the kubelet start  new pods and leading to alternation between running state and crashloopbackoff with the time ranging betwwen 10-12 sec. on the init side, i learnt on how init containers run successfully/completely before the main container starts . this is suitable for migration, dependecies waiting and secret mgt. finally on sidecar, offers the possiblity of having two contaner in one pod  sharing same volume, networking etc
------------------------

Three sharpenings
1. "Kubelet starts new pods" — wrong word, important nuance. The kubelet restarts the container inside the same pod. The pod itself doesn't change — same name, same IP, same identity. Only the container is recreated. That's why you see the RESTARTS counter go up on one pod, not a new pod each time. This matters in production: if your pod's IP changed every restart, every Service endpoint would constantly churn — but it doesn't, because the pod is preserved.
2. Backoff is exponential, not flat. You saw 10–12 seconds because you watched only 3–4 cycles. The actual sequence is 10s → 20s → 40s → 80s → 160s → 300s (capped at 5 minutes). That doubling is what "Backoff" in CrashLoopBackOff means — the kubelet protects the cluster from a thrashing container by waiting longer each time before retrying.
3. Pod ≠ "same filesystem". Each container in a pod has its own filesystem (its image's filesystem). What they share is:

The network namespace (so they have the same hostname, same IP, can talk on localhost).
Any volumes the pod defines, mounted into whichever containers ask for them.

In your lab, the writer and shipper had separate filesystems; they shared /var/log because both mounted the same emptyDir volume there. That's a different thing from "same filesystem". You'll see why this distinction matters when you mount Secrets/ConfigMaps in week 2 — sometimes you want a config available to only one container even within the same pod.
Two missing pieces
You didn't tackle:

The elevator definition of a pod. Try it now in one sentence: "A pod is...". Don't look. Just type.
What you noticed today. Pick one concrete observation — the SandboxChanged event, the emptyDir surviving the restart, the 11-second gap in the events timeline, anything that surprised you. One line.