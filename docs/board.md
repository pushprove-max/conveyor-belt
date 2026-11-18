# The Board

The Board is a local web page that shows the belt: what needs you, the cards on the belt and their steps, the queue,
what landed, the Declined findings and why, what each card cost, and the loop's health. With more than one project on
the machine, it shows the machine's one Conveyor on every tab, each project in its own section of the Control tab, each
Foreman, and a filter and a sort by project on every list.

## Install the Board

By default, Conveyor and the Board run on one machine. The Board reads the belt, the queue, the costs, the usage and
the accounts on this machine, with no ssh. The host file that setup writes is all it needs. Health shows the
machine as **This machine**.

To read the belt from a separate build machine, set `host`, `ssh` and `main` in the host file on the Board's machine
([The host file](setup.md#the-host-file)). The `ssh` target must take a login by key from the Board's machine:
`ssh -o BatchMode=yes <target> true` must work. When the host file names no `ssh` target, or names this machine as
its `host`, the Board reads this machine.

When the Board cannot read the host file, each panel says that it could not read its part. Click its details to see
which part of the host file to correct. `conveyor.sh doctor` names the same fault.

`/conveyor-belt:setup` asks "Start the Board now?" when the Board is not running. Yes starts it. To start it
yourself, run this in your project's checkout:

```sh
conveyor.sh board
```

It installs the Board from the release of Conveyor that setup installed, with the virtualenv that setup filled. It
asks for no password, because **No login on this device** (below) lets you in from this machine. To log in from other
devices, add an admin on the Board's account page. The new user sets their password from a one-time link. The Board
runs as a user service and prints the address to open. `conveyor.sh doctor` also names the address, or says that the
Board is not running. When the project takes a new release, setup, `conveyor.sh install-service` and the engine's
own update start a Board on an older release again on the new one. If the Board still runs older code than the
project, `conveyor.sh doctor` names both commits; `conveyor.sh board` moves the Board to the project's release.

When **No login on this device** is off and no admin has a password, `conveyor.sh board` stops and names the fix. Then
setup asks you for an admin password in Claude Code's prompt. It runs `conveyor.sh board --password-file <file>`,
which adds the admin `admin` with that password (or gives it to an `admin` that has no password yet), deletes the file and starts the Board. The password is never on a
command line.

The address that opens in the browser is always `https://localhost:<port>/`. When the host file says
`{"board": {"lan": true}}` and **No login on this device** is off, `conveyor.sh board` names
`https://<this host>.local:<port>/`. While the setting is on, only `localhost` lets this machine in with no password.

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
- **3D View**: the belt drawn as a conveyor line, each card on the track of its step (`conveyor/README.md`, Belt 3D).
- **Control**: the panels **Projects and Foremen**, **Loop**, **Push landed and full test suite** and **Board**. Loop
  has the loop's state, **Pause <project> after current**, **Stop now and requeue N cards**, the weekly limit bar, and
  today's landed count and cost. Board has the cards in their columns. The machine head has **Pause all projects**.
- **Rules**: the panels **Rules**, **What these rules produce**, **Model prices**, **Held by you or a label** and
  **Open issues**. On Control and Rules, the line that says what an action did, with its Undo, shows in the panel
  where you did it.
- **Tests**: the project's test files.

A panel's head moves and collapses it, and its width menu sets it to Small, Wide or Full. Customize shows or hides
each panel. It never hides Needs you.

The Declined panel's heading has two buttons that dismiss lines for good. **Dismiss all shown (n)** dismisses the
lines that the panel shows now. **Dismiss all (n)** dismisses every line that the panel counts, also the lines it does
not show. Click the button, then click it again. If the lines that the button counts change before the second click,
the button shows the new count and you must click two times again. A new line changes the count of **Dismiss all**.
It changes the count of **Dismiss all shown** only if the panel shows the new line. The lines leave the panel and its count. **Show every line** still shows
them, marked Dismissed.

Customize also sets how the Board writes times and dates, in this browser:

- **Time**: 12-hour ("3:04 PM", the default) or 24-hour ("15:04").
- **Date**: mm/dd/yyyy (the default) or dd/mm/yyyy.

All the Board's times and dates use these settings, the Account page and the Belt 3D clock too. A change shows at once.

**Restart the Board's feed** is in each place that tells you to press it:

- A panel that could not read its data shows the button next to its error text.
- In Health, the button is in the **Data** row. When Health has no data age, the row is **Board's feed**. While a
  panel or a Health check has an error, this row stays out of **N checks fine**.
- When the status mark says **Stale**, **No data** or **Feed stopped**, the button is next to the mark. On a phone,
  it is in **Menu**.

Click the button, then click it again. The text next to the button shows that the feed restarts, and then the result.

**Show**, in the machine bar, picks the project that every tab shows.

## Needs you

- **Retry and Close.** Each blocked card has a **Retry** button (`conveyor.sh retry`) and a **Close** button. Close
  asks once, then closes the card's issue with a comment and shuts the card (`conveyor.sh shut`).
- **Hold.** Each blocked card of an issue has a **Hold** button (`conveyor.sh unblock <issue> --hold`). One click
  holds the issue and takes the card off the belt and out of Needs you. Conveyor keeps the card's work. **Undo**
  releases the issue. A released issue is built in its turn, from the kept work. A main-red fix card has no issue,
  so it has no Hold button.
- **Fix.** A blocked card shows a **Fix** button only when Conveyor can fix the reason itself. A line above the
  buttons says what Fix does. Fix asks once, then runs the fix. These reasons have a Fix:
  - "the kept patch of card ... could not be taken out of the worktree", and "the engine could not compare the
    port with the kept patch". Conveyor cannot use the kept work. Fix runs `conveyor.sh retry <issue> --fresh`: a
    new card builds the issue from nothing.

  A landing conflict ("rebase onto main conflicts") has no Fix button. **Retry** already brings the kept patch onto
  main. A push that fails a check needs a fix on main first. A card that waits for your yes to a visible change has
  **Approve** and **Decline**.
- **The last line of a block.** The last line above the buttons tells you the step to take for that kind of block:
  - A review asked for changes again, the changed tests failed again, or the card's process ended without a result:
    "Retry: a new session gets the open finding (or the failing tests) and starts from the kept work." Retry is the
    fix. You do not have to do anything first.
  - A review that says main does not do what the issue asks, after the card made no change: "Retry: a new session
    gets the reviewer's finding and builds the issue."
  - A landing conflict: "Retry: a new session brings the kept change onto main as it is now." You do not have to
    wait for the conflict to go.
  - A block that needs you first says what to do, then "Then press Retry.". For example: sign in again on the build
    machine, install a tool that is missing, set a model the account can run, make the project's dependencies reach
    the card, finish or release an issue that it depends on, answer a decision or an approval, or add a missing model
    price.
  - Any other block names its reason, then what Retry does: "Blocked because: ... Retry starts a new card, from the
    kept work if there is any."
- **Retried.** After a retry, the card shows "Retried, waiting for its turn" in place of Blocked, with no buttons.
  The card leaves Needs you at the Board's next full read of Conveyor, and a new card builds the issue in its turn.
  This needs the live feed. Without it, the card shows as Blocked until that read. A card that you held is not shown
  as retried: it keeps **Undo** until the Board's next full read.
- **Screenshots.** When the pack sets `review.screenshots` ([Configuration](configuration.md#the-pack)), a card that
  waits for your yes shows the screenshots that your project's own run made of its change, above **Approve**. The
  Board shows only the screenshots made from the change that you approve. A screenshot made before a later change to
  the card does not show. The images stay on the machines of the Board and Conveyor. Conveyor does not take
  screenshots, so a project without them shows none.
- **Queue and Close.** Each entry under "Pipeline changes held for you" has a **Queue** button, which releases
  the issue (`conveyor.sh control release`), and a **Close** button.

## Health and Lanes

- **Flaky tests** and **Kept off card tests** in Health list each test case or file on its own row under **Show
  output**. A row shows the name, a count ("3 re-runs", "Kept off") and the issue filed for it, as a link,
  when there is one.
- A Health row whose error is one line says what failed in a short sentence, for example "The Board could not get
  main from GitHub." Click **Raw error** to read the error as it came, with **Copy output** to copy it.
- **Work now**, at the foot of Health, shows what keeps the Conveyor machine busy now. Open it to read the machine.
  Each card's busy processes come first, grouped by card and step, the heaviest CPU first. Then come the busy
  processes that no card owns, such as another program or a stray test process. A closed card that still runs
  processes shows **closed: left over**, with the command that stops them. **Read again** reads the machine again.
  It is the same list as `conveyor.sh work`.
- A blocked landing in the Fast lane shows its reason on one line. Its log is under **Show output**, as plain text,
  with **Copy output**.

## Set up a new repository

The first time the Board opens for a repository, a box asks you to set each project rule. Its title is
**Set up Conveyor for <owner/repo>**. It has five steps, and a bar at the top names each step:

1. **What to build**: Build, Never build and Split large issues.
2. **Landing**: Land as, Push when a card lands, Test before a push, Dependency guard, New issues start in and Whole
   suite in a card.
3. **Models**: Builder, Reviewer, Judge, Account and Review account.
4. **Limits**: Cards at once and Pause when the weekly limit reaches.
5. **Your yes**: Visible changes need your yes.

Each rule shows its name, what it does and the controls of the Rules tab. The default is already selected, also when
the rule has another value now. To keep the default, click the selected choice or the **default: <value>** button.
A rule is set only when the build machine saves your choice. **Next** sets each rule of the step that is not set yet
to its default, then shows the next step. On the last step it is **Finish**. The footer says how many rules are set.

Each choice is saved when you click it. A model is saved when you pick it, with no **Save**. If you leave before the
end, the rules you set stay set.
**Later**, or Escape, closes the box until the next time the Board opens. While the repository is not set up, a line
at the top says **Conveyor is not set up for this repository yet**. Its **Set up** button opens the box again.

**Finish** records the setup in the project's control record. The box then stops opening. When a newer Conveyor has a
rule that you did not set, the box opens again with only the steps that hold the new rules.

The box does not ask for the machine's setting, Cores kept for you: it belongs to the build machine. The test
command, the product paths and the owner stay with `/conveyor-belt:setup`.

## Rules

The Rules tab holds the settings:

- which issues to build (the P0 to P3 switches, follow-ups and area labels). A main-red fix card is built whatever the
  P0 to P3 switches say, by design: held, every card that meets the red main would wait for good.
- cards at once. A card that only waits on another card does not count, up to as many waiting cards as this
  setting. The On the belt figure leaves these cards out, and a tap on it says how many wait,
- the usage at which no new card starts,
- the builder, reviewer and judge: each a CLI installed on the loop's machine, then a model, then an effort
  ([Models](configuration.md#models)),
- the accounts ([Accounts](#accounts)),
- where new issues start.

A setting changed there shows its new value at once. A value the host refuses goes back, with the refusal beside it.

**Model prices** lists the price of each model the Board knows, in dollars per million tokens: input, output, cache
read and cache write. Each release updates the built-in prices. With no cache write price, a 5-minute cache write
costs 1.25 times the input price. A 1-hour cache write costs twice the input price.

- **Search** finds a model by its ID, its display name or one of its other IDs.
- **Seen but not priced** lists each model ID that this project's sessions used in the last 30 days and that no
  model or alias prices, with its session count. **This is…** marks the ID as a known model: pick the model (the Board
  picks the likely one first). **Add as new model** opens Add model with the ID filled in. Conveyor files one held
  issue to add each price ([Models](configuration.md#models)).
- **Offered with no price** lists each model that a seat runs, or that the project's model list has
  ([Models](configuration.md#models)), and that no model
  or alias prices, with the seats that use it. It has the same two buttons. Conveyor files one held issue to add each
  price ([Models](configuration.md#models)).
- **In use by this project** comes first. Each row has a mark: builder, reviewer, judge, Tests or research lane, or the
  number of sessions that used it in the last 30 days.
- Then **Claude**, **OpenAI** and **Other**, by family, newest first. Older versions fold under "Older Claude models".
  A model's fast mode is the second line of its row.
- **OpenCode** lists the models that OpenCode can run on the build machine. Each says where its price comes from:
  "as OpenCode reports" (the default), "your price" (**Set my price**; **Back to OpenCode's** undoes it), or the
  price of a known model, when you mark the ID with **This is…**. Those not in use and not priced fold under "All
  OpenCode models". An OpenCode model you add with **Add model** has a row like any added model.

**Edit** opens a row in place: the display name, other IDs, and the four prices. **Save** saves the changes and
**Cancel** drops them. A row with your price says "Saved, from the pack" and has **Reset to built-in**, which puts back
the built-in price. Your price wins over the built-in price for every prompt size, in step costs and in the cost of
the day. Fast mode then costs twice your price, until you give it a price of its own with **Edit :fast**.
**Reset :fast** takes that price off: fast mode costs twice your price again, or the built-in price when the model
has no price of yours. The button shows that price. A step priced from your price says "priced from your
override" on its cost line.

**+ Add model** adds a model that the Board does not know: its ID as sessions report it, a display name, a provider,
and its prices. "Same price as…" copies the prices of a known model. An added model is priced like a built-in one, has
an "added" mark, and has **Remove**.

Other IDs (aliases) are for a model that comes back under another ID, for example through a proxy or another
provider (`anthropic/claude-sonnet-4-6`). A session with an alias is priced as its model and shows the model's display
name on the Board. A new display name does not change the model's ID.

Your prices, added models and aliases are saved in the pack (`prices` in `.conveyor/project.json`), so you commit them
with the project. Each change has Undo.

**Visible changes need your yes** is a switch per project, Off by default. On, a card whose change customers or staff
will see stops until its issue has a `Visible change approved:` line. Off, the tab says "off: visible changes land
without your yes".

**Whole suite in a card** is a switch per project, Off by default. Off, a card runs only the test files that it adds
or changes. A card that changes no test file runs 5 of the test files linked to its change. The test files linked to
the landings run before each push, and the whole suite runs only in a release. The tab says "off: a card runs only the
test files it adds or changes (with none, 5 linked to its change), the test files linked to the landings run before
each push, and the whole suite runs only in a release". While **Test before a push** is Off, that line does not
name the run before a push. On, a card runs the whole suite when it cannot find the tests of
its change ([Whole suite in a card](configuration.md#whole-suite-in-a-card)).

**Land as** is **Main** or **Pull request**. Until you set it, it shows the pack's `push.landAs`. Main pushes the
landed cards to the default branch. Pull request pushes them to the branch `conveyor/landing`, and one pull request
from there collects them until you merge it. The tab then says "one pull request from conveyor/landing collects the
cards; merge it to close their issues" ([Land as](configuration.md#land-as)).

**Merge PR** is **Button**, **Release** or **Idle**. Until you set it, it shows the pack's `push.prMerge`. Button
leaves the merge to you, with **Merge** on the Control tab. Release merges the pull request when you make a release.
Idle merges it when no card is on the belt and no issue can be picked. When **Test before a push** is on, the test files
linked to its cards must pass first ([Merge PR](configuration.md#merge-pr)).

**Test before a push** is a switch per project. On, before each push Conveyor runs the test files linked to the
landings since the last push, and a file that fails holds the push. Off, a push runs no test first, and the tab says
"off: a push runs no test first". The switch shows the pack's `push.check` (on in a new project) until you change it
here. Your change goes in the control record and wins over the pack
([Which tests a card runs](configuration.md#whole-suite-in-a-card)).

**Split large issues** has three settings per project: Off, Shadow and On. Shadow is the default. Shadow records what
the Judge would split a large issue into, and builds the issue whole. The tab says "shadow: the verdict is recorded,
and the issue is built whole". On files the slices as follow-ups and holds the issue as their umbrella until the last
slice lands or is already done on main. Off checks no issue ([Split large issues](configuration.md#split-large-issues)).

## Held issues and dependencies

An issue that is not being built is in Held for one of four reasons: **Held by you**, **Held by a label**,
**Skipped by a rule** or **Waiting on #N**. "What these mean", under the Held heading, says where to change each.
An issue that someone outside the project opened shows **Opened by someone outside the project: release it to build
it** in place of **Held by you** ([The control record](configuration.md#the-control-record)).

On the Rules tab, "waiting on another card" opens the waiting list. It shows each waiting card with the cards it waits
on, as "waits on #12 (testing), #13 (landed)". The **Dependency guard** row sets the guard On or Off. With it Off,
each card of the waiting list has **Queue anyway**, which asks once and then sends `control force`.

Each card in the Held and Queue columns has **Depends on…**: type or pick open issues, or remove one (×). The host
writes the issue's `Depends on: #N` line on GitHub (`conveyor.sh control depends`). It refuses a self-dependency, an
issue that is not open, a cycle, or an issue whose card already runs.

## Settings for one card

Each card in the Held, Queue, Building, Review and Needs you columns shows its builder, reviewer and judge. A seat
that is the card's own, not the project's, says "(this card)". You can change a blocked card's settings before you
retry it.

- **Settings** opens a model list and an effort list for each seat. Pick **Project's** to use the project's seat.
  The lists show only the models that the pack allows the seat. **Save** sends each changed seat
  (`conveyor.sh control card`).
- **Pick for me** asks the project's judge to choose the three seats for the issue. The card shows the judge's model,
  effort and reason for each seat. Nothing changes until you press **Apply**. **Discard** drops the choice.

A step that already runs keeps its settings. The next step uses the new ones. [Configuration](configuration.md#settings-for-one-card)
tells more.

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

Push landed, Run full test suite and Release share their results for each commit. When one of them passed on the
commit, the next runs no test: Push landed pushes at once, and the result says "Reused the green run of <time> on
<commit>". After a run on an earlier commit, only the files that failed or changed since then run again, and the
result says "Reran 1 file, reused 2 passed files from <commit>". A change to the test commands runs the whole suite.

**Push now**, beside Push landed, pushes the landed commits at once, with no full test run. Click it, then click again.
It pushes main as Conveyor does after each card when the rule is On: through the project's pre-push hook only. If the
hook fails, nothing is pushed and the card shows in Needs you with the failed check. It is greyed while a full test
run is under way, or when nothing waits for a push. Use Push now for a small change that the card's own tests and the
pre-push hook cover. Use Push landed when you want the whole suite green before the push.

**Merge** shows while the pull request of Land as `pr` is open, whatever the rule Merge PR says. Beside it are the
pull request's number, as a link to it on GitHub, and how many cards it holds. Click it, then click again: Conveyor
merges the pull request at once, with a merge commit. When GitHub refuses the merge (a failed check, a conflict), the
pull request stays open, and GitHub's reason shows beside Merge ([Merge PR](configuration.md#merge-pr)).

## Release

The Release panel on Overview is Small at first. Its width menu sets it to Small, Wide or Full. At Small, each card is
one narrow column. It shows one card for each project that releases with
Conveyor: a project whose `main` has a `docs/releases/` folder. Other projects do not show. When no project releases
with Conveyor, the panel says "No project releases with Conveyor."

The top row of a card shows the project, its newest release tag (or "No release yet"), the number of changes since that
tag, and one status. The status is the first of these that applies: Suite running, Suite failed, Main moved since the
suite, Released, Notes missing, Suite not run, Ready to release.

Under the top row are three numbered steps. Each step has a mark: done, failed, in progress or to do.

1. **Release notes**: `docs/releases/<version>.md` on `main`, "written" or "missing: Draft notes writes them".
2. **Full suite**: the whole suite on the head of `main`. It shows passed or failed, with the commit and the time, or
   "Not run". While the suite runs, a bar shows the test files done of all the test files, with the names of the files
   that failed. A test case that ran out of time shows as "<case>: timed out". A full test run in progress shows here too. When **Release** is enabled, the step also says what
   it does: "Uses the suite that passed at <time> on <commit>", or "Runs the suite first (about N min)".
3. **Release**: the tag and the GitHub release.

When a run stops, each reason that it gave shows under its step: a notes reason under step 1, a suite reason under
step 2, other reasons under step 3.

The version field has the version to release. This is the newest `docs/releases/<version>.md` on `main` that is higher
than the newest tag. If there is none, it is the next minor version after the newest tag. When you type another
version, the card shows the steps and the buttons for that version. When `main` has no notes for the version, a line
under the field says so.

The card has two buttons, in this order. The first writes the notes draft or runs the suite. Its label follows the state: **Draft notes**,
**Run suite**, **Run suite again** or **Run again on the new main**. The second is **Release** with the version (for
example **Release 1.0.0**). Click a button, then click again.

To release from the panel:

1. Make sure that the field has the version to release.
2. If **Release** says "needs release notes docs/releases/<version>.md", click **Draft notes**. Read the draft, then
   commit it to `main`.
3. If **Release** says "needs the whole suite to succeed on main's head (<commit>)", click **Run suite**.
4. Wait for the suite. While it runs, **Release** says "the suite is running (N of M files)". If it fails, **Release**
   says "the suite failed: <count> failures". Fix the failures, then run the suite again.
5. When the notes are on `main` and the suite passed on the head of `main`, **Release** is enabled. Click it, then
   click again.

**Release** is disabled until it can run. Its text says what it waits for.

- **Draft notes**, **Run suite**, **Run suite again** and **Run again on the new main** run `conveyor.sh release-run prep <version>`. Conveyor
  runs `conveyor.sh release-prep <version>` and nothing more. If `main` has no notes for the version, it writes a draft
  of them and stops. Else it runs the suite on the head of `main`: the whole suite, or only the files that failed or
  changed since an earlier suite run ([Releases](releases.md)). An earlier suite run is a release's, a Run full test
  suite's or a Push landed's. When one of them passed on that same commit, no test runs. Step 2 says which: "Reused
  the green run of <time> on <commit>", "Reran 1 file, reused 2 passed files from <commit>" or "Ran the whole suite".
  These buttons do not release.
- **Release** with the version runs `conveyor.sh release-run <version>`. The second click is your yes to the release.
  When the suite of that version passed on the head of `main`, and `main` did not move after it, Conveyor uses that
  pass and runs `conveyor.sh release <version>` ([Releases](releases.md)). Else Conveyor runs
  `conveyor.sh release-prep <version>`, which runs the whole suite first, and runs `conveyor.sh release <version>` when
  the suite passes. The second click's text says which of the two occurs. Nothing else starts a release.
- **Release anyway** shows beside a failed suite on the head of `main`. The first click shows the failed files and
  cases. The second click is your yes to release over them: Conveyor runs `conveyor.sh release-run anyway <version>`,
  and the release names you and the failures. The status of the suite stays failed
  ([A release over a failed suite](releases.md#a-release-over-a-failed-suite)).

**Stop** shows only while a run is in progress. After a second click, it stops the processes of that run. Conveyor
itself continues.

When a card lands while the suite runs, the status stays Suite running, and the suite step says that `main` moved. The
two buttons stay disabled until the suite ends. Then the status is Main moved since the suite, and the button is **Run again
on the new main**. The run does not start again by itself.

**Show N changes** opens the changes on `main` since the tag, newest first, 10 at a time. Each change is one line: the
issue number, as a link, and the issue title.

## Card steps

- A finished review reads "Review 2: passed" or "Review 2: changes asked". A review the judge read says "judge: N
  accepted, M declined". Each finding has an id, E1, E2 and so on, that it keeps from one review to the next. A
  finding that came back after its fix says so, for example "E2 came back after 2 fix rounds".
- **Show output** on a review lists its findings, one row each, in the order the reviewer gave them. A row shows the
  priority (P0 to P3), the finding, and under it the file and line. Click **Proof** to read the reviewer's proof. Click
  **Reviewed lines** to read the lines that the finding names, as that review read them. When the finding names lines
  that the change or a fix round deleted, you also see the deleted lines. These lines stay after the card's worktree is removed. The
  file link goes to main, which can show different code. Each
  other step's output shows as plain text, with its failures first. **Copy output** copies the output as plain text, for a
  review too. This is the same in On the belt, Landed today and Needs you.
- A fix session shows what started it: **Fix 2: review findings**, **Fix 1: reply check**, **Fix 3: main changed under it** or
  **Fix 4: tests failed**. Hover over the label for the full reason.
- A reply-check fix after the build shows on the Build step, "Build · reply check fix" and then "Build · reply check
  fixed". The Fix step shows the other fixes.
- A card in its Test step shows how many tests have run, "142 of 205 tests", and " · 2 failed" when any failed. A test
  command gives the count when it prints `TESTRUN cases=N`, and names each case as it ends with an empty file in
  `cases/ok` or `cases/failed` of its test log folder (`conveyor/README.md`, The test step). With no case count, the
  card shows its test files, "3 of 6 test files". Each test file counts once. If the run ran more test files than it
  selected, the card shows the extra files after the count, "86 of 86 test files · 15 more files than selected". When
  the pack sets `test.list`, the text starts with the list that the run got: "changed: 7 files", or "whole suite" ([Which tests a card runs](configuration.md#which-tests-a-card-runs)).
- A bug card shows "Proof run" on the Build step while its new tests run on main without its fix, with its test files
  run, "297 of 1161 test files". While all the test slots are in use, it shows "waiting for a test slot". No review
  runs then.

## Tests page

The Tests tab shows, from top to bottom: the Test map, Benchmarks: SWE-bench Verified, the figures, the table of
test files, Test edits by cards, Removed by Optimize, Recent actions, Benchmarks, and Settings.

The Benchmarks: SWE-bench Verified part runs [SWE-bench Verified](benchmarks.md) through Conveyor. Pick 1, 5, 20 or
50 tasks, or type any number up to 500, and pick main, a release, or Claude alone. Before you click **Start**, the part
shows the sessions and minutes the run is expected to take. While the run goes, a bar shows the tasks done, and
**Stop** ends it. The results of every version show side by side, one column a version, with a line that says how big
a difference the number of tasks can show. **Compare** shows why two versions differ, task by task.

The Benchmarks part shows the latest [drift watch](benchmarks.md#drift-watch): the cards of the latest engine commit
against the cards of the commit before it, with the number of cards in each group. It says when a group is too small
to mean anything.

The Test map part shows the state of the [test map](configuration.md#the-test-map). A made map shows how many source
files and test files it maps, how many commits it is behind main, when it was made and how long its run took. It
also shows how many test files the map could not map. A folded list gives each of these files with the reason. The
map does not use these files to pick the tests of a card. The other states are "Not made yet", "Off" and "Failed", with the reason. An admin can click **Build the test map** to
make the map now. Before you click, the part names the coverage tool and the time of the last whole-suite run. The
build runs your whole suite once on the build machine, on a test slot. While it runs, a bar shows how many test files
have run, and **Stop** ends the build. When the build ends, the part shows its result. The Board refuses the button to
a member. When the map is off, when `test.map` names a map that your project keeps itself, or when your language has no coverage tool, the part tells you and shows no button.

The figures count the timed files, the files slower than usual and the files that wait more than they work, and give
the slot wait and run time of the card Test steps of 7 days. No test file has a CPU budget. Click the figure of files
slower than usual or that wait, and the table shows those files only, as their filter chip does.

The table shows every test file of the project: each file's CPU seconds, its median, its last runs, the clock time of
its newest run (Last run took; point at it to see when that run was) and its status (Slower than usual, Waits,
Flaky and others). A file with an issue shows a link to it, "#NN". The runs are those of card Test steps and of
whole-suite runs (Run full test suite, Push landed, and the suite of a release). A file with no time yet shows
"Not timed yet" in place of its figures and comes after the timed files. A file with clock times only shows "Wall
only": its test runner's report gives no CPU seconds, so its CPU columns are empty. A file that only whole-suite runs run
(`wholeOnly` in the pack's `test.files`) shows "Whole suite only". Such a file starts other test files, and each of
them is timed on its own. It shows "Runs other test files". It never shows Slower than usual or Waits, and you cannot
optimize it or mark it slow on purpose.

A Wall only file has no CPU seconds because no test runner's report gives CPU time. The status says why and names the
runner from the pack's `test.report`. With no `test.report`, the clock time came from a `TESTRUN sec` line of your test
command with no CPU seconds. CPU seconds come from a `TESTRUN sec` line that `conveyor/tools/testtime.sh` prints.
When your test command runs only this one test file, is one plain command and gets no test list (`test.list` not set,
or `none`), the row has **Record CPU time**. It shows your test command now and the same command wrapped in the
helper. Click **Save the test command** to save it in the pack's `test.command`. Only an admin can save it. The next
run of the file records its CPU seconds, and Wall only goes away. In all other cases the row says why no action can
apply, and shows none. Then wrap each test file's run with the helper in your test script (`conveyor/README.md`, Test
file times).

A Whole suite only file costs more than its own time. A card's Test step never runs it, so a change to it is tested
only by a whole-suite run. The status gives the CPU seconds of the newest whole-suite run on record. To fix it, open
its row and click **Make it run alone**. The issue asks a card to make the file run by itself, or to move what it runs
into test files that the runner can list, and to keep what it tests. Before the card goes to review, Conveyor checks
two things. The pack must no longer mark the file `wholeOnly`. The file must pass when it runs alone with the change,
on a test slot, and Conveyor gives it to the test command as the pack's `test.list` says. When the change removes
the file, Conveyor runs the test files that the change adds or changes. When a check fails, the card is blocked, and
the reason says why. After the card lands, the row no longer shows Whole suite only, and a card's Test step can run
the file.

The Caught column shows how often a test file caught a real bug. Conveyor counts it from the card records: a card
Test step failed in the file, the card landed, and its landed change did not change the file. So the fix went into
the code. When the landed change did change the file, the file was changed to pass. Point at the count to see how
often that happened. A step of a card that did not land counts neither way. A file with 20 runs on record or more
and no catch shows "Never caught anything" in grey text, which is not a status chip. A file that never fails may
check nothing.

A file shows "Fails often" when 2 or more card Test steps failed in it for a reason outside the card's own change.
Conveyor gives each failure a verdict. Flaky: the case failed, then passed when it ran again. Main: the case failed on
main too. Card: the card's own change made it fail, so the test did its job. Fails often counts the flaky and main
failures, and the failures from before Conveyor kept verdicts ("no verdict on record"). It never counts a card
failure. The status of the file says the kinds in grey text, for example "Failed: 1 flaky, 1 failed on main too".
Card failures show apart, as "caught 3 card changes". Point at that text to see the cards. Overview of an open row
lists each failure with its time, its kind, its card and its failing cases.

To fix a file that fails often, open its row and click **Fix failures**. The button shows when the file has a flaky or
main failure. It opens the same issue preview as Optimize, with the title "Fix the failures of the test file
<file>". The issue lists the failing cases, their kinds and the end of their output, and the causes that Judge found.
It asks a card to make the file pass every time and keep what it tests. Its Done-when asks that the failing cases
pass in 10 runs in a row of the file alone on a test slot, and in a run with the other files of the suite. Before
the card goes to review, Conveyor runs the file alone 10 times in a row with the change. When one run fails, the card
is blocked, and the reason names that run. Judge can help first: it reads the recent failures of the file, and its
verdict is stabilise when it finds the cause in the test (shared state, timing, order, environment or a fixture).

A file with hollow cases shows "Hollow". A hollow case passes but proves nothing. The kinds are `mock-echo` (it only
checks that a mock gives back what the mock was told to give), `text-only` (it only checks that a file contains some
text), `no-assert` (it has no assertion) and `defined-only` (it only checks that a value is defined or truthy). For a
JavaScript or TypeScript test file, Conveyor finds the clear cases with no model: a case with no `expect` or `assert`
call, and a case whose only assertions are `toBeDefined` or `toBeTruthy`. When Judge this test ends, its hollow cases
replace these. Click the "Hollow N" filter chip to see only these files. The Judge tab of an open row lists its
hollow cases, each with its kind and the reason.

To fix the hollow cases of a file, open its row and click **Fix hollow cases**. The issue preview lists each hollow
case with its kind and reason. The issue asks a card to make each case assert the behaviour that it names. When
another test already proves that behaviour, the card can delete the case. It then names that test on a line
`COVERED-BY: <test file>: <its case> | <the deleted case>`. Before the card goes to review, Conveyor runs the hollow
check of Judge on the changed file. When a model of another family than the builder's is set up, the check runs on
that model. When the check still finds a hollow case, or a deleted case has no COVERED-BY line, the card is blocked,
and the reason names the cases. The file stops showing Hollow when a later run of Judge names no hollow case.

A file shows "Waits" when its last run took more than 2 times its CPU seconds on the clock. The file waits more than
it works: it sleeps, polls, or waits for a timeout, a lock or the network. Judge reads the clock and CPU seconds of
its recent runs and names each wait on a line `WAIT: <case> | <kind> | <file:line> | <reason>`. To fix the file, open
its row and click **Fix the waiting**. The issue holds the clock and CPU seconds of its recent runs and the waits that
Judge named. It asks a card to remove or shorten the waits and keep what the cases test. Before the card goes to
review, Conveyor runs the file alone 3 times in a row with the change, each run on a test slot. Each run must pass
and take at most 2 times its CPU seconds on the clock. When a run does not, the card is blocked, and the reason names
that run.

A file with no run on record shows "Never run". When Conveyor can tell why, the status says it: the pack's
`tests.patterns` or the test command do not match the file, loading the file fails (with the error), or the file is
skipped (with its skip markers). Open its row for two actions. **Make it run** opens an issue that asks a card to
make the test command run the file, or to fix what stops it. After the Test step of the card, Conveyor checks that
the step ran the file and that the file passed. When it did not, the card is blocked. **Delete it** opens an issue
that asks a card to delete the file. For each case that matters, the card names the test that proves it on a
`COVERED-BY` line. The review of the card checks these lines, as it does for an Optimize card that deletes a file.

The Mutants caught column shows the newest mutation check of a file, as "14 / 20": the check made 20 small changes
(mutants) to the code that the file tests, and the file failed on 14 of them. The column is empty until a check of
the file ends. Point at the count to see when the check ran and on which commit. A check that runs, waits in the
queue or is paused also shows "running", "queued" or "paused". The Mutation tab of an open row shows the state of its check: queued, with
its place in the idle queue; running, with the mutant it runs ("mutant 4 of 20"); paused for a card; or done. It
lists each mutant that survived: the source file and line, the line before and after the change, and "tests still
passed". A surviving mutant shows a change that the tests do not see.

Point at a column heading, or move the keyboard focus to it, to see what the column shows. Click a column heading to
sort the table by that column. Click it again to reverse the order. An arrow shows the column and the direction. Until
you pick a column, the files that need a look come first, then the highest CPU seconds. Type part of a file's path, or
part of a case name, in the search box to see only the files that match it. The search matches file paths and case
names. A row that a case name found shows that case beside the file name. The search and a filter chip work together.

Click a file's name to open its row. The row has four tabs: Overview, Timeline (with its count of events), Judge and
Mutation. Overview shows first. Use the left and right arrow keys to move between the tabs.

Overview starts with a box that says what state the file is in: its CPU seconds now, after which Optimize
cards and by how much each one changed it, and whether its runs are slower or faster than usual. Under it is the
verdict of Judge as a chip with its reason in one line, and **Full report**, which opens the Judge tab. Then come the
buttons for the next step: Judge, Optimize (**Optimize again** after an Optimize landed), **Fix failures** (on a file
with a flaky or main failure), **Fix hollow cases** (on a Hollow file), **Fix the waiting** (on a file that Waits),
**Make it run** and **Delete it** (on a file Never run), **Make it run alone** (on a Whole suite only file), Run and More. The step that the Board suggests is the primary
button. Six tiles follow: the CPU seconds now with the median, the last 4 runs as bars, the last Optimize as a
percentage with its issue and its CPU seconds before → after, the clock time with its clock / CPU ratio, the bugs
caught and the mutants caught (or "not checked"). Point at a bar, or move the keyboard focus to it, to see its CPU
seconds. The failures of the file come next, when it has any. Last, the 3 latest events, with a button that opens
the Timeline.

The Timeline lists every event of the file, newest first: its runs (each with its card's issue, or "whole suite" and
its result), its Optimize issues, the test edits of landed cards and the runs of Judge. The filter chips All, Runs,
Optimize, Test edits and Judge show one kind of event. A test edit shows the issue of its card, as a link, and its
time. A weakened edit has the chip "Weakened". When you open the Timeline, the Board reads the older runs and test
edits of the file from the machine Conveyor runs on, and adds them below the newest. While it reads, the Timeline says
so. If the read fails, the Timeline gives the reason, and the Board reads again the next time you open the Timeline.

The Judge tab shows the newest result of Judge: its verdict once at the top, then its full report. When Judge names
the causes of the failures, the tab lists each one as "<case> | <kind> | <reason>". The Mutation tab
shows the mutation check of the file. A tab's content is never taller than the window under the page head: a long
one scrolls inside its tab.

Judge (Judge this test) and Run (Run this file now) start at once.
Optimize shows the issue first, with the title "Optimize the test file <file>", the file's numbers, its hollow cases,
its surviving mutants (so that the card adds the assertions that catch them) and the newest verdict of Judge, with
the end of its text. Edit it, then click "File this issue". Cancel files nothing. More holds Explain the slowdown,
Mutation check, Keep a case off, Close its issue as done and Mark as slow on purpose
(`conveyor.sh test-settings`). Use the arrow keys to move in the More menu, and Escape to close it.

Mutation check puts the file at the front of the idle queue (`conveyor.sh mutate ask`). It does not start a check.
`conveyor.sh serve` runs the checks of the queue one at a time, and only while no card needs a test slot. When a card
asks for a test slot, the check pauses, and it goes on from its next mutant later. After the files you asked for, the
queue holds the files that the page flags (Never caught anything, or Hollow), then the files checked longest ago
(`conveyor/README.md`, Mutation checks).

An open row also shows its newest action, in a box under its buttons. When Judge ends, its result moves to the Judge tab. When you click Judge, Run or Explain the
slowdown, the box shows at once, with a bar and "Starting", until the build machine answers. A queued action shows a
bar, "Queued, N ahead" and Stop. While it runs, you see its time bar, the time it used, its text as it comes, Stop and
Copy. When it ends, you see its result in the same box. When the build machine refuses the action, the box shows "Not
started" and the reason. With no model for the test actions, Judge and Explain the slowdown send nothing, and the box
says "Set the Tests model first.". Optimize and Mutation check show on a line under the buttons in the same way: sent,
the reason when they are refused, the issue filed, or the state of the check (queued with the files before it, running
with its mutants and its time, then its result). Optimize on a file that runs other test files tells you why it files
no issue. The text of Judge and Explain the
slowdown shows as formatted text: paragraphs, bold, lists and code. Copy copies the text as the model wrote it. A
Judge result starts with "Verdict:" and the verdict. When the verdict is speed up, split, merge or delete, click
"Optimize with this verdict" to open the Optimize issue with that verdict and its text. When the verdict is
stabilise, the same button opens the Fix failures issue, with the causes that Judge found. The page scrolls to the
issue, which shows the verdict, and the cursor is in its text.

The Timeline lists each Optimize issue filed for the file, and each older "Speed up the test file" issue. Each shows
its link and its state: open, building, blocked (with the reason), landed (with the commit), or closed without
landing. A landed issue also shows the fix of its card (sped up, split, merged into a file, or deleted), the CPU
seconds of the file before → after the fix with the change as a percentage, and "Helped" or "Did not help". When the
file ran since the fix landed, it also shows the median CPU seconds of those runs. The first run after the fix has a
mark in the table's Last runs and in the Timeline, while the row still shows that run. When a mutation check of the
file ended before the fix landed and another ended after it, a landed issue also shows the mutants caught before and
after ("Mutants caught before: 9 / 20, after: 14 / 20").

Test edits by cards shows what each landed card did to a test file that the project already had, newest first. A
new test file is not in it. Each entry shows the issue of the card, the file, when the card landed and the counts:
assertions removed, expected values changed in kept assertions, skip, only or todo marks added, timeouts raised and
cases deleted. Conveyor reads shell test files and JavaScript and TypeScript test files. A file of another kind shows
"Edited, not read". The Weakened filter, which shows first, shows the edits with one of these counts above zero. All
edits shows every edit. Weakened edits on many cards show a pattern: tests that were made weaker to get green. The
Timeline of an open row lists the edits of its own file.

A file that an Optimize deleted, or merged into another file, is not in the table. "Removed by Optimize", below the
table, shows it with its last numbers, its issue and the test files that now have its cases. For a deleted file,
these are the test files that the review of its card named.

Recent actions is closed until you open it. Its heading shows how many actions run and how many are queued. It lists
the test actions and the Optimize issues, newest first, each with its state. Click a file name in it to open the row
of that file.

Each row has a checkbox. The checkbox in the heading selects every file that the search and the filter show. With one
file or more selected, a bar at the bottom of the screen shows how many, with Judge, Optimize, Run, Mutation check and
Clear. Judge, Run and Mutation check ask for all the selected files at once. After Mutation check, the rows show
"queued", and the bar says that a check starts only when no card needs a test slot. Optimize shows one issue for each file, each with a title and a text that
you can edit, and "File N issues" files them. Cancel files nothing. When you click an action, the bar shows a bar and
"sent to the build machine" until the build machine answers. Then it shows the answer for each file, and each file
that it left out, with the reason: Optimize leaves out a file that runs other test files, and Judge needs a model for
the test actions. For each Judge and Run that started, the bar shows its state: queued with how many are before it,
running with its time bar, and then its result (the verdict, or passed or failed). Open "Its text" to read the text.
For each Mutation check, the bar shows the state of the check of that file. One action takes at most 20 files.

An Optimize card picks the fix: speed the file up, split it, merge it into another test file, or delete it. It does
not need a test that fails on main. A file it keeps must pass in fewer CPU seconds than its median, else the card is
blocked with "the file is not faster" and both numbers (`conveyor/README.md`, Bug cards: the new tests fail without
the fix). Each file of a split must pass, and the files' CPU seconds summed must be at most the old file's plus a
start-up allowance for each new file. For a delete or a merge, the review names the
test that still covers each case of the file. Each file of an action on many files gets its own action or issue, and
its own answer. At most 3 test actions run at once. The others wait as queued and start in the order asked. Stop
takes a queued one off before it starts.

Settings is closed until you open it. It holds "Model for Tests actions" (Judge and Explain the slowdown need it),
Test limits (the files slow on purpose in the pack), and Auto-file,
which shows the test rules (`conveyor.sh testrules`) and the log of what they filed (`conveyor/README.md`, Test
actions).

## Accounts

The Health panel shows the usage of every Claude account. The Rules tab sets which account a project's cards and
reviews use (`conveyor/README.md`, Accounts).
