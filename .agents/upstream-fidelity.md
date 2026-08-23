# Upstream fidelity

This repo is a fork of [mattpocock/skills](https://github.com/mattpocock/skills). The
reason to stay close to upstream is not merge hygiene for its own sake — it is that
upstream keeps refining the wording of these skills, and a paragraph we have rewritten
is a paragraph whose next refinement we will not receive. The conflict resolves in
favour of whatever we already had, silently, and the improvement is lost.

`CLAUDE.md` carries the rules. This file carries why each one exists.

## Two mechanisms that make the failure likely

**Regenerating is a model's default.** Ask a model to add three clauses to a paragraph
and it rewrites the paragraph. It is not a decision anyone makes, so it is not caught by
deciding not to do it — only by measuring afterwards. Run the word diff even when the
edit feels obviously safe; that is precisely the state in which every incident below
happened.

**A caveat is invisible to the word diff.** Appending *"except when X"* to an inherited
rule destroys zero words and scores perfect. The rule is still weaker on every run that
reads it. This is why a feature needing an exception belongs in its own file rather than
as a clause bolted onto the rule it undermines.

## The measurement

Split both versions of a passage into one word per line and diff them. Lines starting
with `<` are upstream words destroyed.

```bash
git show upstream/main:PATH | sed -n 'Np' | tr ' ' '\n' > /tmp/a
sed -n 'Mp' PATH | tr ' ' '\n' > /tmp/b
diff /tmp/a /tmp/b
```

The baseline is `upstream`, never `HEAD`. Measured against `HEAD`, restoring upstream's
wording and rewriting it look identical — both replace the whole line. A review that
used `HEAD` once reported a restore as a violation for exactly this reason.

The metric ranks candidates; it does not validate them. One proposed patch for the
`:95` incident below scored 1 destroyed word and was subtly ungrammatical — it paired
the verb *close* with the object *source contract*. Read the result.

A rename is a claim about the mechanism, not voice. Say what the new name asserts, then
check it: *compatibility form* asserts this form exists for compatibility, when the form
kept for compatibility is the old one. Renaming one half of a pair is the risk case —
`new`/`old` sit on an axis and cannot be swapped without obvious nonsense, `compatibility`/
`old` sit on none. And *deliberate* is a classification, not a verdict: a delta kept because
it was intended has been labelled, not checked.

## Incidents

**`af55d4f` — a tidy-up moved three rules.** A rewrite of the seam-rule prose also
dropped `unless instructed otherwise` from the `ready-for-agent` label instruction and
replaced the "stay in step 4" behaviour. One target, three rules moved. The commit that
fixed it had to restore a boundary nobody had intended to change. Two of the three, that
is: `#25` later examined the `unless instructed otherwise` drop on its merits and ratified
it, holding that a user's authority to override an agent is general and needs no
advertised alternative output contract. That one stays removed, now on purpose.

**`9f3515c` — voice consistency cost 48 words.** The commit added three genuine rules to
`to-tickets`, and rewrote upstream's wide-refactor paragraph "in place" so it would match
the positive voice of the new ones. The mechanism it described never changed. It
destroyed 48 of upstream's 159 words to land three additions; a later restore did the
same job destroying 4. The commit message and the changeset also disagreed about which
form the contract ticket retires, and the resulting prose hedged by asserting both.

The restore measured the paragraph and kept one of the rewrite's renames as a deliberate
term change: upstream's *new form* had become the *compatibility form*. The name sat on
the wrong side of the pair — the form kept alive for compatibility is the **old** one,
which unmigrated call sites still need; the new form is the destination that survives.
That inversion wrote two sentences backwards. `425a492` caught one, where the docs page
and changeset had the contract ticket retiring the wrong form. The other survived every
later pass: *"the compatibility form is never withdrawn while a named batch is still
outstanding"* protects the form nobody would delete, and only reads as correct if you take
the term to mean its opposite. Both were reverted to upstream's wording on 2026-08-02,
taking the paragraph from 4 destroyed words to 2.

The lesson is the one the metric section already states, with a cost attached: the word
diff tells you whether you rewrote something, never whether the rewrite is right. A rename
that destroys two words can seed a defect that outlives three review passes.

**`#11` — a narrowing became a rewrite.** Staged calibration needed upstream's
`Do NOT close or modify any parent issue.` narrowed, because on a local tracker the
checkpoint is written into the parent file. The whole sentence was replaced instead:
7 of 8 words destroyed. It lost the explicit word *close* at the same moment the feature
introduced `closed` as a checkpoint state. The fix was not a better sentence but moving
the feature into `STAGED-CALIBRATION.md`, after which upstream's sentence returned
byte-identical with no caveat attached.

**Line 43 — nearly reverting our own deliberate work.** A proposal to delete
`to-tickets/SKILL.md`'s independent-model paragraph, on the grounds it was "only nuance"
already held in `CALIBRATION.md`. `git log -S` showed `5dd5609` and `99e164d` had each
deliberately hoisted that wording into `SKILL.md`, and `RISK-SHAPES.md` documents the
duplication as intentional: *"The skill states the rule in shorter words; these shapes
are what it covers."* The deletion would also have left `independent` undefined in two
always-loaded lines. Nothing about upstream was involved — the fork's own wording was
load-bearing, and only the history said so.

## Fork-owned regions

`README.md`'s install section is fork-owned: take ours on conflict without
deliberating. Upstream ships in Claude Code's official marketplace, so their install
collapses to `claude plugins install mattpocock-skills`. This fork runs its own
single-plugin marketplace, so it needs `/plugin marketplace add faviann/skills` then
`/plugin install faviann-skills@faviann`. Their commands cannot work here and never
will.

Their *structure* can transfer even though their commands can't. The 2026-08-02 merge
adopted upstream's audience-split `<details>` layout while keeping the fork's commands,
which is the shape to aim for. Read their version while you are resolving the conflict —
you are already looking at both — and copy the layout if it is better. Do not schedule it
as a separate review; if it ever becomes one, drop it and always take ours.

## What this cannot do

Pull-request CI now runs the repository's shell suites, but the one eval — hand-run,
covering a single skill's discrimination — enforces none of these prose rules. They are
read by agents, not executable checks. They make a violation provable once someone
looks; they do not make anyone look.
