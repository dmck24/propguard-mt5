# Session workflow

Current task-specific user instructions take precedence over this policy.

## Startup confirmation

At each new session, inspect instructions and available controls read-only, then
ask the user to confirm these settings before substantive work:

- Brain provider, model, and reasoning effort.
- Proposed Hands models, effort, and task allocation (or no separate Hands when
  the task does not benefit from them).
- Outside Oracle provider, model, and review route.

Label each setting as verified by an exposed control, user-confirmed, or unknown.
A cached model list is supporting information, not proof of the running model or
effort. Never claim to set or verify controls that are not exposed. Preserve
confirmations and authorizations already given in the current session; explicit
task-specific effort instructions take precedence.

## Work and review

Brain owns the plan and integration; suitable Hands perform bounded tasks inside
the working session. Match Hands models and effort to task complexity and the
tools actually available. Brain generally uses one supported reasoning level
below the highest for cost/benefit, unless the user specifies otherwise. Model
names and effort options evolve: verify current choices, do not hardcode them.

Oracle is an outside model from the other provider. It reviews **both the plan
before implementation and the final results**, approving or requesting revisions.
Revise and resubmit when requested. Do not add an internal Oracle role, duplicate
review hierarchy, or orchestration ceremony. Useful local checks remain required
and do not substitute for outside review. If review is unavailable, report it as
pending. Provisional implementation requires an explicit current user override;
do not infer authorization merely from unavailable review.

Prepare concise user-relayed review packets: scope, plan or diff, acceptance
criteria, evidence, test results, risks, and open questions. Record the review
decision and revisions. Contact an outside agent or share repository material
only when the user authorizes that specific agent and material. Oracle approval
does not authorize disclosure, messages, publication, or operational actions.

## Repository checks

Preserve acceptance criteria, guard behavior, audit logs, evidence, and security
constraints. Run checks appropriate to the change; report results and blockers
honestly. Work in an isolated branch or checkout without resetting, stashing,
switching, or overwriting an active or dirty checkout. Keep historical evidence
intact. Repository work alone does not authorize VPS access, MT5 operation,
deployment, account changes, or trading; obtain explicit task authorization for
such actions and preserve all applicable safety gates.
