# The Board

The Board is a local web page that shows the belt: what needs you, the cards on the belt and their steps, the queue,
what landed, the Declined findings and why, what each card cost, and the loop's health. With more than one project on
the machine, it shows the machine's one Conveyor on every tab, each project in its own section of the Control tab, each
Foreman, and a filter and a sort by project on every list.

## Install the Board

The Board reads the belt over ssh, from the `ssh` target of the host file, this machine's settings file. Set its
`host`, `ssh` and `main` ([The host file](setup.md#the-host-file)). The `ssh` target must take a login by key from this
machine: `ssh -o BatchMode=yes localhost true` must work. Then, in a terminal, in your project's checkout, run:

```sh
conveyor.sh board
```

It installs the Board from the release of Conveyor that setup installed, with the virtualenv that setup filled. When
the Board has no admin yet, it first adds one, `admin`, who logs in from other devices, and asks for the password
twice. The Board runs as a user service and prints the address to open. After the project takes a new release, run
`conveyor.sh board` again to move the Board to it.

## Users and authenticator codes

The Board is behind a login over HTTPS. Each user is an admin or a member. An admin adds users, who set their own
password from a one-time link. Each user can turn on codes from an authenticator app, with one-time recovery codes.

**No login on this device** is on by default. The Board opened on the machine it runs on then needs no login, and acts
as an admin named "this device". This device is a connection from a loopback address (`127.0.0.0/8` or `::1`, as the
server's socket sees it) to `localhost` or a loopback address on the Board's port. No header, such as
`X-Forwarded-For`, counts. Every other device logs in. Turn the switch off when a tunnel or a proxy on the same machine
serves the Board, because its requests come from a loopback address. An admin sets the switch on the account page.

## Tabs and panels

- **Overview**: the panels Needs you, On the belt, Queue, Landed today, Release, Declined, Health, Lanes, Cost and Metrics. The
  tab shows the count of cards stopped for you, "Overview · 4".
- **Control**: the panels **Projects and Foremen**, **Loop**, **Push landed and full test suite** and **Board**. Loop
  has the loop's state, **Pause <project> after current**, **Stop now and requeue N cards**, the weekly limit bar, and
  today's landed count and cost. Board has the cards in their columns. The machine head has **Pause all projects**.
- **Rules**: the panels **Rules**, **What these rules produce**, **Model prices**, **Held by you or a label** and
  **Open issues**. On Control and Rules, the line that says what an action did, with its Undo, shows in the panel
  where you did it.
- **Tests**: the project's test files.
- **Belt 3D**: the belt drawn as a conveyor line, each card on the track of its step (`conveyor/README.md`, Belt 3D).

A panel's head moves and collapses it. Customize shows or hides each panel and sets its width. It never hides Needs
you. **Restart the Board's feed** is in the Health panel.

**Show**, in the machine bar, picks the project that every tab shows.

## Needs you

- **Retry and Close.** Each blocked card has a **Retry** button (`conveyor.sh retry`) and a **Close** button. Close
  asks once, then closes the card's issue with a comment and shuts the card (`conveyor.sh shut`).
- **Queue and Close.** Each entry under "Pipeline changes held for you" has a **Queue** button, which releases
  the issue (`conveyor.sh control release`), and a **Close** button.

## Health and Lanes

- **Flaky tests** and **Kept off card tests** in Health list each test case or file on its own row under **Show
  output**. A row shows the name, a count ("3 re-runs", "2 runs over budget") and the issue filed for it, as a link,
  when there is one.
- A Health row whose error is one line says what failed in a short sentence, for example "The Board could not get
  main from GitHub." Click **Raw error** to read the error as it came, with **Copy output** to copy it.
- A blocked landing in the Fast lane shows its reason on one line. Its log is under **Show output**, as plain text,
  with **Copy output**.

## Rules

The Rules tab holds the settings:

- which issues to build (the P0 to P3 switches, follow-ups and area labels). A main-red fix card is built whatever the
  P0 to P3 switches say, by design: held, every card that meets the red main would wait for good.
- cards at once,
- the usage at which no new card starts,
- the builder, reviewer and judge: each a CLI installed on the loop's machine, then a model, then an effort
  ([Models](configuration.md#models)),
- the accounts ([Accounts](#accounts)),
- where new issues start.

A setting changed there shows its new value at once. A value the host refuses goes back, with the refusal beside it.

**Model prices** lists the price of each model the Board knows, in dollars per million tokens: input, output and
cache read. Cache writes follow the built-in multipliers. Each release updates the built-in prices. To price a model
that is newer than your release, or to change a price, type the model and its three prices and press Save. Change
on a row fills in its model and prices. Your price is an override: it is saved in the pack (`prices` in
`.conveyor/project.json`), so you commit it with the project. It wins over the built-in price of that model for every
prompt size, in step costs and in the cost of the day. Fast mode then costs twice your price. A step priced from an override says "priced from your override" on its cost line. Remove override puts
back the built-in price. OpenCode steps keep the cost that OpenCode reports.

**Visible changes need your yes** is a switch per project, Off by default. On, a card whose change customers or staff
will see stops until its issue has a `Visible change approved:` line. Off, the tab says "off: visible changes land
without your yes".

## Held issues and dependencies

An issue that is not being built is in Held for one of four reasons: **Held by you**, **Held by a label**,
**Skipped by a rule** or **Waiting on #N**. "What these mean", under the Held heading, says where to change each.

On the Rules tab, "waiting on another card" opens the waiting list. It shows each waiting card with the cards it waits
on, as "waits on #12 (testing), #13 (landed)". The **Dependency guard** row sets the guard On or Off. With it Off,
each card of the waiting list has **Queue anyway**, which asks once and then sends `control force`.

Each card in the Held and Queue columns has **Depends on…**: type or pick open issues, or remove one (×). The host
writes the issue's `Depends on: #N` line on GitHub (`conveyor.sh control depends`). It refuses a self-dependency, an
issue that is not open, a cycle, or an issue whose card already runs.

## Push landed and Run full test suite

The Rules tab's **Push when a card lands** rule is Off by default. Conveyor lands each card on main and pushes when you
press **Push landed** or **Push now**. Turn the rule On, and Conveyor pushes each card on its own after it lands.

With the rule Off, a card that landed leaves the belt. It is not in On the belt, Belt 3D or `/units` ON THE BELT. Landed
today shows it as "Landed, waiting for Push landed", and the Control tab counts it in "N landed, not pushed". Its Push
step stays to come until you press Push landed or Push now. With the rule On, a landed card stays on the belt as
"pushing" until Conveyor pushes it.

**Push landed** and **Run full test suite** are on the Control tab, which shows "N landed, not pushed". Push landed runs
the project's full test suite, the `test.full` of the pack (the project's settings, `.conveyor/project.json`), on
main. Setup sets `test.full` to your test command in a new pack. Green, it pushes the landed commits that the run tested.
Red, it pushes nothing: it runs each failed case alone and judges it. A case that passes alone goes on the flaky-test
record. A case that fails in the code becomes a P1 fix card. A case that fails for the machine or the network is
declined, with its reason. **Push anyway**, beside a red result, pushes those commits after a confirm. **Run full test
suite** runs the suite and pushes nothing. A project with no `test.full` shows both buttons greyed
(`conveyor/README.md`, The full test suite).

**Push now**, beside Push landed, pushes the landed commits at once, with no full test run. Click it, then click again.
It pushes main as Conveyor does after each card when the rule is On: through the project's pre-push hook only. If the
hook fails, nothing is pushed and the card shows in Needs you with the failed check. It is greyed while a full test
run is under way, or when nothing waits for a push. Use Push now for a small change that the card's own tests and the
pre-push hook cover. Use Push landed when you want the whole suite green before the push.

## Release

The Release panel on Overview is as wide as Landed today. Customize sets it to wide or full only. It shows one card for each project that releases with
Conveyor: a project whose `main` has a `docs/releases/` folder. Other projects do not show. When no project releases
with Conveyor, the panel says "No project releases with Conveyor."

The top row of a card shows the project, its newest release tag (or "No release yet"), the number of changes since that
tag, and one status. The status is the first of these that applies: Suite running, Suite failed, Main moved since the
suite, Released, Notes missing, Suite not run, Ready to release.

Under the top row are three numbered steps. Each step has a mark: done, failed, in progress or to do.

1. **Release notes**: `docs/releases/<version>.md` on `main`, "written" or "missing: Draft notes writes them".
2. **Full suite**: the whole suite on the head of `main`. It shows passed or failed, with the commit and the time, or
   "Not run". While the suite runs, a bar shows the test files done of all the test files, with the names of the files
   that failed. A full test run in progress shows here too. When the button is **Release**, the step also says what
   the button does: "Uses the suite that passed at <time> on <commit>", or "Runs the suite first (about N min)".
3. **Release**: the tag and the GitHub release.

When a run stops, each reason that it gave shows under its step: a notes reason under step 1, a suite reason under
step 2, other reasons under step 3.

The version field has the version to release. This is the newest `docs/releases/<version>.md` on `main` that is higher
than the newest tag. If there is none, it is the version in `.claude-plugin/plugin.json` when that is higher. Else it
is the next minor version. When you type another version, the card shows the steps and the button for that version.

The card has one button. Its label follows the state: **Draft notes**, **Run suite**, **Release** with the version (for
example **Release 1.0.0**) or **Run again on the new main**. Click it, then click again.

- **Draft notes**, **Run suite** and **Run again on the new main** run `conveyor.sh release-run prep <version>`. Conveyor
  runs `conveyor.sh release-prep <version>` and nothing more. If `main` has no notes for the version, it writes a draft
  of them and stops. Else it runs the suite on the head of `main`: the whole suite, or only the files that failed or
  changed since an earlier suite run ([Releases](releases.md)). Step 2 says which: "Reran 1 file, reused 2 passed
  files from <commit>" or "Ran the whole suite". These buttons do not release.
- **Release** with the version runs `conveyor.sh release-run <version>`. The second click is your yes to the release.
  When the suite of that version passed on the head of `main`, and `main` did not move after it, Conveyor uses that
  pass and runs `conveyor.sh release <version>` ([Releases](releases.md)). Else Conveyor runs
  `conveyor.sh release-prep <version>`, which runs the whole suite first, and runs `conveyor.sh release <version>` when
  the suite passes. The second click's text says which of the two occurs. Nothing else starts a release.

**Stop** shows only while a run is in progress. After a second click, it stops the processes of that run. Conveyor
itself continues.

When a card lands while the suite runs, the status stays Suite running, and the suite step says that `main` moved. The
button stays hidden until the suite ends. Then the status is Main moved since the suite, and the button is **Run again
on the new main**. The run does not start again by itself.

**Show N changes** opens the changes on `main` since the tag, newest first, 10 at a time. Each change is one line: the
issue number, as a link, and the issue title.

## Card steps

- A finished review reads "Review 2: passed" or "Review 2: changes asked". A review the judge read says "judge: N
  accepted, M declined".
- **Show output** on a review lists its findings, one row each, in the order the reviewer gave them. A row shows the
  priority (P0 to P3), the finding, and under it the file and line. Click **Proof** to read the reviewer's proof. Each
  other step's output shows as plain text, with its failures first. **Copy output** copies the output as plain text, for a
  review too. This is the same in On the belt, Landed today and Needs you.
- A fix session shows what started it: **Fix 2: review findings**, **Fix 1: reply check**, **Fix 3: main changed under it** or
  **Fix 4: tests failed**. Hover over the label for the full reason.
- A reply-check fix after the build shows on the Build step, "Build · reply check fix" and then "Build · reply check
  fixed". The Fix step shows the other fixes.
- A card in its Test step shows how many tests have run, "142 of 205 tests", and " · 2 failed" when any failed. A test
  command gives the count when it prints `TESTRUN cases=N`, and names each case as it ends with an empty file in
  `cases/ok` or `cases/failed` of its test log folder (`conveyor/README.md`, The test step). With no case count, the
  card shows its test files, "3 of 6 test files".
- A passing Test step with test files over their CPU budget shows one chip, "3 slow files" or "1 slow file". It is a
  note, not a warning: the card still lands. Click the chip to open the list under the step. Each row shows the file
  name, its folder under it and its CPU seconds, "63.3 CPU s". The slowest file is first. When all the files went over one
  budget, a line above the rows gives it (`test.fileBudget` in the pack, or the file's own budget).

## Tests page

The Tests tab shows every test file of the project: each file's CPU seconds, its median, its last runs, the clock
time of its newest run (Last run took; point at it to see when that run was) and its status (Over budget, Slower than
usual, Waits, Flaky and others). The runs are those of card Test steps and of whole-suite runs (Run full test suite,
Push landed, and the suite of a release). A file that no run ran yet shows "Never run" and dashes. A file that only
whole-suite runs run (`wholeOnly` in the pack's `test.files`) shows "Whole suite only".

Click a column heading to sort the table by that column. Click it again to reverse the order. An arrow shows the
column and the direction. Until you pick a column, the files that need a look come first, then the highest CPU
seconds. Type part of a file's path in the search box to see only the files that match it. The search and a filter
chip work together. A row opens to show its runs, each marked with its card or "whole suite", to set a budget for the
file or to mark it slow on purpose (`conveyor.sh test-settings`). Test limits holds the Load limit (`maxLoad`, in the host file)
and the project's test budget (in the pack).

An opened row has the test actions. "now" runs at once and files no issue. "issue" files an issue. Judge this test and
Explain the slowdown need a model for the test actions ("Model for Tests actions"). Auto-file shows the test rules
(`conveyor.sh testrules`) and the log of what they filed (`conveyor/README.md`, Test actions).

## Accounts

The Health panel shows the usage of every Claude account. The Rules tab sets which account a project's cards and
reviews use (`conveyor/README.md`, Accounts).
