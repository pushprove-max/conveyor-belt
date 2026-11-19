# adversarial

All three angles, in this one review.

Angle 1 of 3, bypass and trust: can any check, guard, proof or gate in this change be skipped, forged or made to pass when it should refuse? Look at every input the change trusts.

Angle 2 of 3, behaviour: wrong results, edge cases, failure paths and callers the change breaks. Trace each changed branch with a concrete input.

Angle 3 of 3, tests and words: a changed behaviour with no test, a test that cannot fail, and comments, rule text or docs the change leaves untrue.

# review

Correctness bugs, security problems and missing tests in the changed lines.

# every pass

List every finding you can defend, worst first. After each one, look for the same mistake elsewhere in the diff and list those too.

What can go wrong: paged or background work needs timing cases, and cut or converted text needs limit and odd-data cases; a change that lacks the cases its kind needs is a finding. New tests: every test the change adds names the bug it would catch, in its name or a one-line comment; one that names none, or whose named bug its assertion cannot catch, is a finding. Proxy tests: a test the change adds or changes that runs other test files or the suite runner, runs the real loop, or polls a real process until a condition holds, with no comment beside it that says what a direct check cannot show, is a low finding (P3). Unrequested placeholder UI: a control that is always disabled, a stub screen, or copy such as 'coming soon', 'not available yet' or 'in a later update' that the issue does not ask for is a P1 finding, whatever a code comment says; matching a mockup is not a reason. Gate readers: a fix to a reader that guards a gate must be an allowlist that accepts only the shapes it fully understands and refuses every other one with an error naming the line; a fix that adds support for one more input shape instead is a class-miss finding. Smaller change: is there a smaller change that fully solves the problem? A yes is a finding that names the smaller change and why it fully solves the problem; it is never a reason to cut scope the problem needs.

Severity: critical is P0, high is P1, medium is P2, low is P3. A gap in documentation or wording is low unless it hides a real defect; then rate the defect. Only critical, high and medium findings hold the review. In each finding body, add one line "Class search: rg <arguments>": a read-only rg search from the repository root whose hits are every place with the same mistake, this one among them. Every finding names the exact failing input or command that shows it; leave out any you cannot, and never invent one.
