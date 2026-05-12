Week 4 focused on how Kubernetes behaves in production environments: how workloads are scheduled, scaled, protected, monitored, and recovered automatically. The labs moved beyond simply deploying applications into understanding the operational behavior of a real cluster.

1. Resources, Requests & Limits

Learned how Kubernetes manages CPU and memory through resource requests and limits.

Key Understanding
Requests determine scheduling guarantees.
Limits cap maximum resource consumption.
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
Important Behaviors Observed
Memory Limit → OOMKill

You demonstrated a pod being terminated after exceeding its memory limit.

Observed:

Reason: OOMKilled
Exit Code: 137

Meaning:

kubelet terminated the container
memory limits are enforced aggressively
CPU Limit → Throttling

Unlike memory:

CPU overuse does NOT kill containers
Linux cgroups throttle CPU usage

Impact:

slower applications
increased latency
2. Scheduling & Placement

Learned how the Kubernetes scheduler decides where workloads run.

nodeSelector

Used node labels to force workloads onto specific nodes.

Example:

nodeSelector:
  tier: app
Pod Anti-Affinity

Demonstrated spreading workloads across nodes.

Observed:

one pod stayed Pending
cluster refused to violate anti-affinity rules

Key lesson:

Hard anti-affinity can improve resilience but may reduce scheduling flexibility in small clusters.

Taints & Tolerations

Demonstrated node protection.

Without toleration:

untolerated taint

With toleration:

pod successfully scheduled

Key lesson:

taints repel workloads
tolerations allow workloads onto protected nodes
Topology Spread Constraints

Distributed replicas evenly across nodes/zones.

Key lesson:

Kubernetes attempts balanced placement
exact equality is not guaranteed
maxSkew controls imbalance tolerance
3. Horizontal Pod Autoscaler (HPA)

Created real CPU load and observed live autoscaling.

Observed:

replicas: 1 → 10
Key Learnings
HPA depends on metrics-server
HPA uses resource requests as scaling baselines
scaling up is aggressive
scaling down is intentionally slow
Production Understanding

Autoscaling improves:

resilience
performance
cost efficiency
4. Health Probes

Learned the three core Kubernetes probes.

Probe	Purpose
Startup Probe	protects slow-starting apps
Readiness Probe	controls traffic routing
Liveness Probe	restarts unhealthy containers
Critical Operational Lesson
Readiness should validate dependencies.
Liveness should only validate process health.

Bad liveness probes can create production outages.

5. Jobs & CronJobs

Learned how Kubernetes handles:

finite workloads
scheduled workloads

Observed successful CronJob executions and completed jobs.

Real-world use cases:

backups
scheduled maintenance
ETL pipelines
cleanup jobs
reporting
6. Observability & Troubleshooting

This was the most operationally important part of Week 4.

Core Debugging Workflow
Describe
kubectl describe pod <pod>

Best for:

scheduling failures
image pull issues
probe failures
OOMKilled analysis
Logs
kubectl logs <pod>
kubectl logs <pod> --previous

Best for:

application crashes
restart loops
Events
kubectl get events --sort-by=.lastTimestamp

Best for:

cluster-wide troubleshooting timeline
Metrics
kubectl top pod
kubectl top node

Best for:

resource analysis
identifying hot workloads
Major Production Scenarios You Observed
OOMKilled

Container exceeded memory limits.

ImagePullBackOff

Registry/DNS/authentication failures.

FailedScheduling

Affinity, taints, or resource conflicts.

HPA Scaling Events

Dynamic autoscaling behavior.

Metrics API Failures

Metrics-server instability affecting autoscaling.

Biggest Week 4 Takeaways
Kubernetes Is a Scheduling Platform

Most production behavior revolves around:

scheduling
reconciliation
resource management
Resource Tuning Matters

Poor requests/limits create:

instability
throttling
wasted capacity
node pressure
Reliability Is Automated

Kubernetes continuously:

restarts workloads
removes unhealthy pods
redistributes traffic
scales applications
Observability Is a Core Platform Skill

Real platform engineering work heavily involves:

reading events
inspecting pods
debugging scheduling
analyzing scaling behavior
troubleshooting resource failures
Your Current Skill Level

You can now confidently discuss:

Kubernetes scheduling
taints/tolerations
affinity rules
autoscaling
probes
troubleshooting workflows
operational debugging
resource management
real production failure patterns