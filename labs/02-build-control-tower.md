# Module 2: Extend the Control Tower with App Builder

**Estimated time:** 35-40 minutes, after VM setup.

Add **one table, one form, one view, and one navigation entry** to your
installed Control Tower app. Compare two supplier offers without approving
recovery or starting execution. App-builder creates the two illustrative
offers during the approved build so the comparison view starts with data.
Also enrich the default **Active Supplier Recovery Offers** view with the
six useful comparison fields. Keep the separate comparison view for its
saved column order and ship-date/cost sorting.

Use only the [extension requirements](prompts/Supplier-Recovery-Offer-Extension-app-spec.md)
for this run. 

## Before the timer: prepared VM

Your facilitator should have prepared:

- Node.js, PAC CLI, Azure CLI, GitHub Copilot CLI, and a rehearsed compatible
  version of the model-apps plugin with app-builder available.
- A local checkout containing this file and the simplified requirements.
- Your assigned DEV URL and workshop account, with System Administrator
  access in this isolated training DEV and authentication in PAC/Azure CLI.
- The full unmanaged `PPCCAgenticOperationsControlTower` solution, its app,
  USD currency, and the Supplier F / Clam Chowder case with a Pending decision
  and at least 30 affected units.

If setup is missing, ask the facilitator rather than installing/upgrading tools
or repairing the base solution during the build. The
[Microsoft Learn setup guide](https://learn.microsoft.com/en-us/power-apps/maker/model-driven-apps/model-driven-app-external-tools)
and [shared prerequisites](../../prereqs.md) are preparation references.
Never use a presenter's environment URL or the managed TARGET.

## Step 1: Open the existing app and capture the baseline

1. Open <https://make.powerapps.com>, select your assigned DEV environment,
   and open **PPCC Agentic Operations Control Tower**.
2. Open the seeded **Supplier F / Clam Chowder** case. Confirm its Recovery
   Decision is **Pending**. Record the case and decision identifiers.
3. Record the current case/decision states and the current Carrier Operation,
   Carrier Attempt, and Execution Evidence records/states for later comparison.
   The agent can help read and summarize these without modifying them.

Do not approve, reject, request revision, delete the case, or start execution.
If the app/case is missing or the decision is not Pending, stop for facilitator
help; do not create a replacement or edit seed data.

## Step 2: Start Copilot in the workshop checkout

In PowerShell, use your actual checkout path:

```powershell
Set-Location "C:\github\ppcc26-apps-automations-agents"
pac org who
az account show --query "{Account:user.name,Tenant:tenantId}" --output table
copilot
```

Confirm PAC shows the assigned DEV URL and Azure CLI uses your workshop
identity/tenant. The agent will also verify the actual Dataverse identity.
If they do not match, stop for facilitator help.

At the **Copilot prompt**, enter `/skills` and confirm **app-builder** is
available. If you installed the plugin during preparation, restart Copilot
before checking. Do not start a new-app workflow.

## Step 3: Paste the bounded extension request

Replace `<MY-DEV-URL>` with your assigned DEV URL before pasting.
The requirements already fix the schema and UI choices; you do not need to
redesign them or choose production security/validation mechanisms.

```text
Use the app-builder skill to extend the installed PPCC Agentic Operations
Control Tower in my workshop DEV environment: <MY-DEV-URL>.

Use @prompts\Supplier-Recovery-Offer-Extension-app-spec.md
as the complete requirements for this lab.

Confirm the target and workshop identity, then retrieve the existing app.
Use the existing unmanaged PPCCAgenticOperationsControlTower solution and its
publisher/ppcc prefix. Store generated work under
.artifacts\app-builder\supplier-recovery-offers-extension.

Add only the specified Supplier Recovery Offer table, one Main form, one
active-offer comparison view, navigation in the existing app, and the two
specified illustrative offer rows using app-builder sample data.
Update the default Active Supplier Recovery Offers view to include Offer
Name, Disruption Case, Offer Status, Promised Ship Date, Recoverable Quantity,
and Incremental Cost while retaining its Active filter. Existing extra
columns may remain; exact column order and saved sorting are not required
on that default view. Retain the separate comparison view for its specified
column order and saved ship-date/cost sorting.
Include the specified document-with-price-tag Fluent-style SVG table icon
and show it on the Supplier Recovery Offers navigation entry. Preserve all
existing app, table, and navigation icons.
Include the specified new-component descriptions, full-width multiline
Analyst Notes, and sample-note tradeoffs within the same build and checks.
Use the supplied design choices; do not restart a requirements interview.
Use the prepared administrator account with no role changes.

Preserve existing components, records, roles, and the landing page, except
for the explicitly requested offer default-view column update.
No new app/page, case-form edit, second view, business rule, plug-in,
automation, additional sample rows, or export is requested.
Offers must not approve decisions, change approval/execution state, contact anyone, or create carrier
or evidence records. This is a training exercise, not production validation.

Follow required review gates. Show the proposed changes, limitations, and
dry-run plan before writes, and request explicit build approval. Stop for a
target mismatch, unexpected existing work, or unsupported core change.
Include the exact two offer rows, verified seeded case and USD currency,
and actual VM-date-relative calendar dates in the reviewed plan.
After approval, apply the schema-only data stage without samples, verify the
actual relationship policy, then use the supported full build with sample
data, publish, and verify both the extension and the two created offers.
Do not create offers before approval or before the relationship-safety gate
passes. Do not create duplicates or modify existing seed records.

Separate app-builder completion from manual workshop acceptance.
Navigation must open the offer table and include the selectable comparison
view; I can select that view manually. Automatic default-view configuration
is not a build gate. Limit stock-view edits to the specified offer Active
view; disclose and obtain approval for any enrichment effects on its Inactive
view. Preserve other tables' views and do not create a second authored view.
Date-only display with the actual storage behavior reported is allowed.
Read back the actual relationship cascade policy; stop if it is parental,
unsafe, or unverified rather than substituting a different relationship.
Record MF-01 through MF-04 with owners, actions, expected results, and status.
Do not claim full acceptance before I complete the manual steps.
```

Keep the existing workspace if a run fails. Do not rerun against another
environment using the same downloaded app files; use a fresh, separately
named workspace for each environment.

### Continuing a run stopped during planning

If the previous run stopped before writes because default-view selection
could not be authored, use the revised requirements rather than starting
another app or table. Before resuming, back up the local files that will be
refreshed under the same lab's `.artifacts` directory; do not overwrite earlier
evidence. Keep the workspace's environment binding intact.

Paste this at the Copilot prompt, replacing `<MY-DEV-URL>`:

```text
Continue the existing Supplier Recovery Offers simplified planning run using
the app-builder skill and the updated simplified requirements:
@labs\agentic-control-tower\docs\specs\PPCC26-Supplier-Recovery-Offer-Extension-app-spec-simplified.md

Target my workshop DEV: <MY-DEV-URL>. Reconfirm the environment, prepared
administrator identity, existing app, unmanaged solution/version, and ppcc
publisher. Use the existing supplier-recovery-offers-simplified workspace.

Preserve the previous plan, spec, and baseline before refreshing the existing
app download in that same workspace. If the offer table now exists, the
workspace is bound elsewhere, or another unexpected change is found, stop
and present a reviewed resume plan; do not overwrite or duplicate work.
Refresh the read-only preservation and business-state baseline.

Reapply only the simplified extension intent. Preserve the landing page,
existing components/navigation/data/roles, and identify maintenance writes.
Include the specified document-with-price-tag Fluent-style SVG table icon
and its navigation assignment; preserve all existing icons.
Carry forward the specified descriptions, readable Analyst Notes layout,
and sample-note tradeoffs without additional participant steps.
Include the two specified sample offers, resolved seeded case/USD bindings,
and concrete VM-date-relative dates in the revised review. Inspect existing
offers and receipts before planning insertion; do not duplicate rows or
reset any participant changes.
The earlier automatic-default-view blocker is now MF-01: include the named
comparison view and let me select it manually. Also enrich the existing
Active Supplier Recovery Offers view with the six comparison fields, keeping
its Active filter; exact order and saved sorting are not required there.
Retain the named comparison view for its saved column order and date/cost
sorting. Show this narrow exception to view preservation in the plan and
disclose any Inactive-view changes for explicit approval. Do not alter other
tables' views or remove the comparison view. Report actual date storage
and relationship policy; unsafe or unverifiable cascade behavior remains
a stop condition.

Regenerate lint, the full preview, the design document, and the actual
dry-run plan. Show them and the MF-01 through MF-04 follow-ups before writes.
Request explicit build approval. This continuation request is not approval
to apply or publish.

Only after approval, build, publish, and verify the supported extension.
First apply schema without samples and verify the relationship policy;
then create only the two approved offers through the supported app-builder
sample-data phase. Do not change roles, edit the case form, add automation,
export a solution, or change approval/execution state. Report app-builder
completion separately from the pending manual workshop acceptance.
```

## Step 4: Review and approve

Check the proposed plan before approving Dataverse writes:

| Check | Expected |
| --- | --- |
| Target | Your assigned DEV, existing unmanaged solution, existing app |
| Table | Offer Name, case lookup, promised ship date, quantity, cost, three-value status, optional notes |
| UI | One Supplier Recovery Offer Main form, one Active-offer view, one navigation entry displaying the table's document-with-price-tag Fluent-style SVG icon |
| Icon verification | Icon web resource and table/navigation assignments read back; existing icons preserved; participant visual check tracked in MF-01 |
| Polish | Purposeful descriptions on new components; full-width, three-row Analyst Notes; sample notes explain earlier/higher-cost versus later/lower-cost alternatives |
| Sample data | Exactly two specified offers; same verified seeded Supplier F / Clam Chowder case and active USD; explicit Received status, quantities/costs, and recorded VM-date +3/+7 calendar dates |
| View selection | Navigation opens the offer table; comparison view is selectable; manual selection is allowed |
| Default list | Active Supplier Recovery Offers includes all six comparison fields and its Active filter; extra existing columns may remain; exact order and saved sorting are not required there; separate comparison view retained for those guarantees |
| Preservation | Original app/page/components/data/roles retained; necessary maintenance writes identified |
| Follow-ups | MF-01 through MF-04 list owners, exact actions, expected results, and current status |
| Not requested | No case grid, second view, new roles, validation plug-in, automation, export, additional sample rows, or seed-record edits |
| Authority | Offers cannot approve or execute recovery |

The skill may require intermediate reviews. Use the supplied requirements
to answer them; do not waive required approvals or authorize unrelated work.
Date storage behavior and API-level validation limitations must be reported,
not silently claimed as production guarantees.
An unavailable default-view setting or genuine DateOnly storage option is
not a core blocker under the documented manual-selection/date-display paths.
An absent cascade-policy option is not proof of failure either, but the
actual relationship must be read back as referential/non-parental. Stop if
that safety requirement fails or cannot be verified.

Approve when the core scope and preservation plan match. Let the agent build,
verify the schema-only relationship safety gate, create the two approved
offers through app-builder's sample-data phase, publish, and verify.
Case/currency binding must use the supported sample-data path; if it cannot,
stop rather than creating parent records or using a separate loader/API patch.
If a core item is unsupported or fails, retain the error and workspace and
request a reviewed recovery plan. Never delete the existing
solution, replace a form/page, or duplicate the offer table to get past a failure.

**App-builder checkpoint:** The published existing app has the new offer
form, selectable comparison view, and navigation with the specified offer
icon. Its default Active view also includes the six comparison fields and
retains the Active filter. The icon web resource and table/navigation assignments have been read
back. All new/changed components
belong to the existing solution. Metadata, membership, preservation, date
behavior, relationship policy, and the protected-state baseline have been
checked. Both illustrative offers have been created and read back with their
row IDs, expected case/USD bindings, dates, quantities, costs, Received status,
and Active state recorded. If these supported checks pass, report
**app-builder portion complete; manual acceptance pending**. Report failures and unverified checks
explicitly; do not claim this checkpoint from build success alone.

Use a follow-up checklist under the existing workspace. MF-01 is default-list
field verification, comparison-view selection, and visual offer-icon verification; MF-02 is published form
behavior; MF-03 is participant-owned
sample-offer inspection/comparison/status changes; MF-04 is landing-page and
authority preservation after that exercise. Record evidence and status for each.
On retries, inspect the offers and previous receipt before insertion. Do not
blindly rerun sample creation or reset participant edits; partial/conflicting
data requires a reviewed resume plan and fresh approval for further writes.

## Step 5: Check the form and compare the sample offers

1. **MF-01:** Refresh the app and open **Supplier Recovery Offers** from
   navigation. Confirm its icon is the specified document-with-price-tag
   Fluent-style icon, not the generic stock table icon. Inspect **Active
   Supplier Recovery Offers** and confirm name, case, status, ship date,
   quantity, and cost are visible with the Active filter. Created On may
   remain; exact order and saved sorting are not required there. Select the named
   **Supplier Recovery Offers** comparison view in the view picker.
   Automatic selection is not required. Do not manually edit stock views or
   author another view as a workaround; the planned Active-view enrichment
   belongs in the reviewed builder scope. A facilitator may separately review
   supported default-view configuration, including any table-wide impact.
   Use **New** to open its Main form; a related grid on the case is not required.
2. **MF-02:** Check that the form requires Offer Name, Promised Ship Date, Recoverable
   Quantity, Incremental Cost, and Offer Status. Disruption Case and Analyst
   Notes are optional on the form; select the same seeded Supplier F case
   in the unsaved form to check the lookup without editing that case.
   Confirm Analyst Notes is a readable full-width multiline area.
   With the other required values filled, confirm quantity **0** and a
   negative cost are rejected.
   An invalid value may be rejected by the field control before Save.
   Discard the unsaved form without creating an extra record. Seeded rows
   do not prove manual New/save behavior, and these checks do not certify
   every API write path.
3. **MF-03:** Inspect the two records app-builder created. Confirm the same
   seeded **Supplier F / Clam Chowder** case and **USD** on both:

   | Field | First offer | Second offer |
   | --- | --- | --- |
   | Offer Name | Faster partial recovery | Lower-cost recovery |
   | Disruption Case | Same verified seeded Supplier F case | Same verified seeded Supplier F case |
   | Promised Ship Date | Recorded build VM date +3 days | Recorded build VM date +7 days |
   | Recoverable Quantity | 30 | 30 |
   | Incremental Cost | USD 120.00 | USD 40.00 |
   | Offer Status | Received | Received |
   | Analyst Notes | Workshop example only; not a supplier commitment. Earlier ship date at higher incremental cost. | Workshop example only; not a supplier commitment. Later ship date at lower incremental cost. |

   Compare the actual dates and row IDs with the build receipt; do not
   recalculate them from a later test date or create duplicate offers.
   If either row is missing or incorrect, stop and request a reviewed
   recovery plan rather than manually inserting replacements.
   These are alternative offers, not quantities to add together or evidence
   of real supplier commitments.
4. Open the **Supplier Recovery Offers** view. Confirm both rows show name,
   case, status, ship date, quantity, and cost, sorted by ship date then cost.
5. Change the first offer to **Shortlisted**, save, and then to **Not Selected**.
   It should remain in the view while Active. Unlike the original Open Offers
   exercise, this view deliberately includes every offer status.
6. **MF-04:** Confirm the original landing page and navigation still work.
   Reopen the original case/decision. Confirm the decision is still Pending
   and compare case/decision states, carrier/attempt records, and evidence
   with Step 1. Apart from the two approved offer rows, no protected business
   records should have been created or advanced by seeding/changing offers,
   and nothing should have been approved. Do not use approval or execution
   controls.

## Completion and optional work

You have completed the required exercise when the new table/form/view and
navigation with the specified Fluent-style offer icon are published, both
sample offers exist and compare correctly,
the manual form/status checks pass, the original app still works, and the
baseline comparison confirms no approval/execution
effects. The [six acceptance checks](../docs/specs/PPCC26-Supplier-Recovery-Offer-Extension-app-spec-simplified.md#illustrative-data-and-acceptance)
in the simplified spec are the completion contract.
Keep **app-builder completion** and **full workshop acceptance** as separate
results. All four manual follow-ups must pass before claiming the latter;
MF-01 permits manual comparison-view selection but also requires the visual
icon, enriched default-list fields/filter, and comparison-view column,
filter, and sorting checks.

If time remains, separately review and approve **one** optional task:
add Offers by Disruption, or use the supported form designer to add the
related offers grid to the existing case form. Neither is required to pass.
No role changes or custom validation code are part of this variant.

A facilitator-rehearsed default Main-form preference is also optional under
the simplified spec's preservation conditions; manual form selection remains
allowed. It is separate from default-view selection and adds no required
lab step. Presenter discussion of richer behaviors belongs in the
[speaker notes](../docs/speaker-notes-supplier-recovery-offers-simplified.md),
not in the participant build scope.

If the build cannot finish, the facilitator may provide an approved completed
full-solution checkpoint. Record that you used it: inspecting that result is
not the same as completing the agentic build. Still perform the offer
comparison and authority checks.

## Facilitator notes for the fresh-environment rehearsal

- Record the participant checkout revision, plugin/tool versions, solution
  version, exact environment/identity, first-run duration, number of questions,
  and manual recovery steps. Keep receipts under the lab's `.artifacts`.
- Start with the offer table absent and a fresh workspace; do not reset a
  previous environment by deleting seeded business data.
- Review exactly two offer sample rows, resolved existing case/USD bindings,
  and concrete VM-date-relative dates before build approval. Use app-builder
  sample data only after the schema-stage cascade readback passes. Record
  inserted IDs and verify no duplicates on recovery; do not seed parent data.
- Retain the complete full-solution DEV/TARGET model for the workshop, but
  do not run checker/export or deploy TARGET during this module.
- The workshop README still points to the original Module 2. Open this
  sibling explicitly for the comparison run. Use
  [simplified Module 6](06-run-deploy-and-replay-simplified.md) for the reduced
  inventory and carry forward the manual acceptance evidence. The original
  Module 2, requirements, and Module 6 remain unchanged for comparison.
- Keep default-view selection, date storage, and cascade-control issue
  candidates separate from acceptance receipts. Logging a future tooling bug
  does not complete a follow-up or authorize a safety workaround.
