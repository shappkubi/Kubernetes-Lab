Week 5 Summary — Failure, Upgrades & Disaster Recovery

This week focused on real production operations and cluster lifecycle management. The labs moved beyond deploying applications into maintaining, recovering, and upgrading Kubernetes platforms safely.

1. Node Maintenance & Availability Protection

Practiced:

cordon
drain
uncordon
PodDisruptionBudgets (PDB)

Key learnings:

cordon prevents new scheduling
drain safely evicts workloads
PDBs protect application availability during voluntary disruptions
unmanaged pods require --force
DaemonSets are ignored during drains

Operational takeaway:

Safe node maintenance depends on replicas, readiness probes, and properly designed PDBs.
2. etcd Backup & Recovery

Performed:

etcd snapshot creation
snapshot verification with etcdutl

Key learnings:

etcd stores Kubernetes cluster state
snapshots are critical for control plane recovery
snapshot verification is part of operational hygiene

Commands practiced:

etcdctl snapshot save
etcdutl snapshot status

Operational takeaway:

Without etcd backups, cluster state recovery becomes extremely difficult.
3. Kubernetes Cluster Upgrade Workflow

Completed a full kubeadm-based cluster upgrade.

Practiced:

kubeadm upgrade planning
control plane upgrade
worker node upgrade
draining worker nodes
restarting kubelet
version validation

Key learnings:

upgrade order matters
control plane upgrades happen first
kubelets follow later
version skew rules matter
upgrades should progress environment-by-environment

Operational takeaway:

Production upgrades require planning, validation, rollback readiness, and controlled node maintenance.
4. Disaster Recovery Concepts

Explored:

GitOps recovery
Velero concepts
recovery strategies

Simulated:

namespace deletion
workload recreation from saved manifests

Key learnings:

Git can act as the recovery source of truth
recovery automation is more important than backups alone
rebuilding from code is preferred over manual recovery

Operational takeaway:

Modern Kubernetes DR combines Terraform, GitOps, Velero, and etcd backups.
5. GitOps Recovery Simulation

Demonstrated:

saving manifests as YAML
deleting workloads
restoring workloads from declarative configuration

Key learnings:

desired state management
reproducibility
infrastructure/workload recovery from code

Operational takeaway:

GitOps enables consistent, repeatable, and automated recovery workflows.
Production Mindset Developed

This week introduced real operational thinking:

maintenance windows
upgrade sequencing
disruption management
rollback planning
disaster recovery
infrastructure reproducibility
operational safety

Transition achieved:

Deploying applications
→
Operating and maintaining production Kubernetes platforms