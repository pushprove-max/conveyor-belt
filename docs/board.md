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

On a narrow screen, the row of tabs is wider than the screen and shows no scroll bar: swipe it sideways to reach the other
tabs.

- **Overview**: the panels Needs you, On the belt, Queue, Landed today, Release, Declined, Health, Lanes, Cost and Metrics. The
  tab shows the count of cards stopped for you, "Overview · 4". The browser tab's title shows the same count,
  "(4) Conveyor Board", also while the page is in a background tab. With no card stopped, the title is "Conveyor Board".
- **3D View**: the belt drawn as a conveyor line, each card on the track of its step (`conveyor/README.md`, Belt 3D).
- **Control**: the panels **Projects and Foremen**, **Loop**, **Push landed and full test suite** and **Board**. Loop
  has the loop's state, **Pause <project> after current**, **Stop now and requeue N cards**, the weekly limit bar, and
  today's landed count and cost. Board has the cards in their columns. The machine head has **Pause all projects**.
  Above the columns, each open parent issue is one row: its title, its parts done of all with a bar, and each part
  being built with its step. Open the row to see each part as landed, building, waiting or blocked, with **Show its
  card**. Each part also keeps its own card in its column, so a blocked part is also in Needs you
  ([Issues](commands.md#issues)).
- **Rules**: the panels **Rules**, **What these rules produce**, **Model prices**, **Held by you or a label** and
  **Open issues**. On Control and Rules, the line that says what an action did, with its Undo, shows in the panel
  where you did it.
- **Tests**: the project's test files.
- **Benchmarks**: the project's SWE-bench runs and their arms ([Benchmarks tab](#benchmarks-tab)).
- **Self-heals**: the Self-heals list of each project on a page of its own ([Self-heals tab](#self-heals-tab)). The
  tab shows the count of entries on the list, "Self-heals · 5".

Keys on the page:

- `1` to `5` open Overview, 3D View, Control, Rules and Tests.
- `n` goes to Needs you.
- `/` goes to the filter of the Board panel, and opens the Board panel if it is collapsed.
- `?` shows the list of keys. Escape closes it, and the focus goes back to where it was.

The keys do nothing while you type in a field, and with Ctrl, Alt or Meta.

The Queue panel lists the issues that Conveyor builds next, in order. Under them are two groups, each a heading with
its count: **Waiting on another card (N)** and **Built, waiting for your PROD deploy (N)**. A group is closed until
you click its heading. It stays open when the Board gets new data. The length of the panel counts only the issues
that Conveyor builds next, so the two headings also show when a group is long.

A long list in Needs you, Landed today, Declined, Cost or Metrics shows as many rows as the panel's length. Under the
list are **Show 5 more** (the panel's length) and **Show all (N)**, where N is the number of items in the list. This is
the one **Show all** of the panel. It also shows all of a panel that you made shorter with its lower edge. The panel's
foot shows how many items it shows of all its items, for example "10 of 58". When the list shows all its items, the
foot has **Show fewer**, which shows the first rows again. A batch of cards is one item. In Needs
you and Declined, **Show 5 more** adds the new rows under the rows that you see, and those rows do not change: an
F-number explanation that you opened in Declined stays open.

A panel's head moves and collapses it, and its width menu sets it to Small, Wide or Full. Customize shows or hides
each panel. It never hides Needs you.

A running card's step and its action change on the Board at once. Its cost, tokens, reply count and time since its
last output can be up to 15 s behind. If the page cannot keep its live connection open, it reads the Board's data
every 15 s, and these figures can be up to 30 s behind.

On the belt, a running card shows the model of its step with the effort beside it, for example "Claude Opus 5.5 at
high". When the effort is not known, it shows the model alone.

A new issue shows in Queue when the loop next asks GitHub for the open issues, before each pick. When the loop does not
run, it shows when the Board's feed next asks GitHub. An issue that you release shows in Queue when the Board next reads
Conveyor. A card that the loop picks shows on the belt at once, with its title, issue and step, and its issue leaves
Queue. Until the next snapshot is made, it shows "new card: details come with the next snapshot" in place of its model, and it has no cost or track.

The Declined panel's heading has two buttons that dismiss lines for good. **Dismiss all shown (n)** dismisses the
lines that the panel shows now. **Dismiss all (n)** dismisses every line that the panel counts, also the lines it does
not show. Click the button, then click it again. If the lines that the button counts change before the second click,
the button shows the new count and you must click two times again. A new line changes the count of **Dismiss all**.
It changes the count of **Dismiss all shown** only if the panel shows the new line. The lines leave the panel and its count. **Show every line** still shows
them, marked Dismissed.

The Declined panel shows declined findings only. The Self-heals list, the Docs list and the dropped entries are on the
[Self-heals tab](#self-heals-tab).

**File as issue** on a Declined line files the finding as an issue, and Conveyor builds it in its turn. Click it, then
click it again. If you do not click it again in 5 s, it shows **File as issue** again and the next click only asks
again.

Customize also sets how the Board writes times and dates, in this browser:

- **Time**: 12-hour ("3:04 PM", the default) or 24-hour ("15:04").
- **Date**: mm/dd/yyyy (the default) or dd/mm/yyyy.

All the Board's times and dates use these settings, the Account page and the Belt 3D clock too. A change shows at once.
The `/units` pane on the Board's machine also uses the last **Time** you set.

The status mark in the head tells you how new the data is:

- **Live**: the Board's feed is open and sends each change as it happens.
- **Polling**: the feed is not open, and the page reads the Board's data again at each refresh. **Updated** shows the
  age of the data.
- **Stale** or **No data**: the page does not get new data.
- **Feed stopped**: the feed's heartbeat stopped. The page can still show data that a feed message brings.

When the mark says **Stale**, **No data** or **Feed stopped**, a line under the head tells you what to do. When it
says **Live** or **Polling**, there is no line.

**Restart the Board's feed** is in each place that tells you to press it:

- A panel that could not read its data shows the button next to its error text.
- In Health, the button is in the **Data** row. When Health has no data age, the row is **Board's feed**. While a
  panel or a Health check has an error, this row stays out of **N checks fine**.
- When the status mark says **Stale**, **No data** or **Feed stopped**, the button is next to the mark. On a phone,
  it is in **Menu**.

Click the button, then click it again. The text next to the button shows that the feed restarts, and then the result.

When the Board gets a new version, an open page loads it again by itself if you are not using the page. You are
using it when a field has the cursor, a field has text that you typed (also on another tab), a button or a question
waits for you to confirm, or a request has no answer yet. Then the page shows **New version.** and a **Reload** button next to the
status mark, and keeps what you did. The page loads again by itself when you finish, for example when you clear the
field, or when you go to another browser tab. Click **Reload** to load the new version at once.

When a script file that the whole page needs does not load, the page shows "The page could not load all of its files."
and a **Reload** button in place of the panels. Click **Reload** to try again. This holds for the files that
**app.js** lists and the page loads after it. When **app.js** itself does not load, the page shows no such message and
no button: reload the page in the browser. When only the file of one panel does not load, the other panels still draw,
and that panel says "This panel is missing". Reload the page to load it again.

A reload keeps these, in this browser tab only, until you close the tab or someone signs in again in any tab of
this browser:

- how many rows each list shows after a **Show N more** button (**Show 5 more**, **Show 10 more** or
  **Show 100 more**) or **Show all**, for each project that **Show** picks and for every project,
- an answer, a condition or a reason (**Why not**) that you typed in Needs you and did not send,
- the text in the Board's filter, for each project.

After any **Show N more** button, the cursor goes to the first new row. If that row is in a closed group, the
cursor goes to the heading of that group.

**Show**, in the machine bar, picks the project that every tab shows.

The Control, Rules, Tests and Benchmarks tabs hold one project at a time. With **Show** at **All projects**, each of their
panels that holds one project shows no project's data. It says that the tab holds one project's settings. The first
such panel of the tab that is not hidden lists a button for each project; the others say where that choice is. A
button sets **Show** to that project, the same as picking it in the machine bar. **Projects and Foremen** on Control
lists every project's rows, so it stays as it is.

## Needs you

- **A snapshot that is behind.** When a project's card records changed after its last snapshot was made, Needs you
  and On the belt each show "As of <time>, the belt has changed since." under what they show. Needs you then lists
  the cards that the card records hold blocked or waiting for your yes now, and On the belt counts the cards that the
  loop builds now (none when the loop does not run). When **Show** is set to that project, its row in **Projects and
  Foremen** on Control shows the same count in its "cards at once" as On the belt.
- **A blocked card.** A blocked card shows, in this order: why it failed, in one sentence; the first finding of its
  review, the first failed test file with its first failure line, or, when a run of the project's checks failed before
  any test ran, the output of those checks; the next step; what **Fix** does, when it has Fix; then its
  buttons. Under the buttons, open **The full reason and every step** to read the other findings and
  their full proof, what Retry does, the card's output, the step where it failed, its track, every step and its
  reviews. It stays open or closed as you left it when the Board reads Conveyor again. A card that the project's
  checks blocked a second time, after their one fix session, has no failed test run: the output of the checks is in
  that closed part, not next to the one-sentence reason.
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
  main. If the issue's section of what customers or staff will see changed since the review, and the kept patch no
  longer applies to main, Retry builds the issue from nothing. If the kept patch applies, Retry builds on it and
  reviews it again. A push that fails a check needs a fix on main first. A card that waits for your yes to a visible change has
  **Approve** and **Decline**.
- **The next step.** The line above the buttons tells you the step to take for that kind of block:
  - A review asked for changes again, the changed tests failed again, or the card's process ended without a result:
    "Retry: a new session gets the open finding (or the failing tests) and starts from the kept work." Retry is the
    fix. You do not have to do anything first.
  - A review that says main does not do what the issue asks, after the card made no change: "Retry: a new session
    gets the reviewer's finding and builds the issue."
  - A landing conflict: "Retry: a new session brings the kept change onto main as it is now. If the issue's section
    of what customers or staff will see changed since the review, and the kept change no longer applies to main, the
    new card builds the issue from nothing." You
    do not have to wait for the conflict to go.
  - A block that needs you first says what to do, then "Then press Retry.". For example: sign in again on the build
    machine, install a tool that is missing, set a model the account can run, make the project's dependencies reach
    the card, finish or release an issue that it depends on, answer a decision or an approval, or add a missing model
    price.
  - Any other block names its reason, then what Retry does: "Blocked because: ... Retry starts a new card, from the
    kept work if there is any."
- **The Foreman has it.** When the Foreman takes a blocked card, it writes a note on it (`foreman.sh note`, see
  [The Foreman](foreman.md)). The card then shows "Foreman has it" in place of Blocked, and the note and its age
  ("Foreman: traced run in progress, then hand land and retry · 5 min ago"). These cards come after the cards that
  wait for you, here and in the Needs you column of Control, where the note takes the place of why the card failed
  and the cards are under the heading "Foreman has it". A card that waits for your answer to the Foreman's picker
  stays with the others and shows "Waits for your answer:" and the note. The Board reads the note from the
  snapshot, as /units does. A retried card shows "Retried, waiting for its turn" with no note. A card that you hold
  shows Blocked with no note, and keeps the Undo of the Hold. A landed or shut
  card leaves Needs you. When the Foreman session that wrote the note ends or loses the role, the note goes away
  within five minutes, and a card that is still blocked shows as Blocked again.
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
- **Dependencies that cannot land.** An issue that waits for another issue whose card was shut shows here. No card
  builds that issue, so the wait does not end. The line says who shut the card and what to do: run
  `conveyor.sh retry <issue>` to build it, or remove it from the `Depends on:` line. When the shut issue is an open
  follow-up of an issue on that line, close the follow-up. An issue that `conveyor.sh control force` lets past its
  wait does not show here.
- **Models with no price.** One line for each project counts the models that the belt runs or offers with no price.
  **View in Model prices** shows only that project on the Board and opens its list on the Rules tab, where you add
  each price ([Models](configuration.md#models)).
- **Engine stopped.** When a stop signal has held a project's engine for more than a minute (state T in `ps`), the
  engine starts no card. One line says so and gives the command that resumes the engine and each stopped process
  under it: `kill -CONT` with their process IDs. Run it on the machine where the engine runs.

## Health and Lanes

- **Flaky tests** in Health lists each test case on its own row under **Show output**. A row shows the name, a count
  ("3 re-runs") and the issue filed for it, as a link, when there is one.
- **Plugin problems** in Health shows when a Foreman noted a problem in Conveyor itself, in `plugin-bugs.md` in its
  folder. Each note is one row: the time, the card and what the Foreman saw. Fix the problem, or file it as an issue
  in the repository of Conveyor. Then click **Dismiss** to remove that note from `plugin-bugs.md`, unless you filed it
  with **File on GitHub**, which removes the note. When the Board says it filed the issue but could not remove the
  note, click **Dismiss**. Dismiss does not file an issue, and it keeps the other notes. When no
  note is left and no link to a filed issue shows, the pane goes away.
- To file a note, click **File on GitHub** in its row. A preview opens below the note. The title is the first clause
  of the note. A note made only of an unchecked cause takes its title from the first clause of the cause. The body holds
  the note, the plugin version, the engine commit and the system. The cause, when the note has one, is the last line of
  the note in the body, as "Cause (not checked):". The card name names your project, so the body shows it as `<card>`.
  You can change the
  title and the body. Nothing is filed until you click **File the issue**. The issue goes to the repository that
  `.claude-plugin/plugin.json` names. Click **Cancel** to close the preview. A note that names its issue, as in
  "filed as #449", is filed already, so it has no **File on GitHub**.
- Before the Board files the issue, `conveyor/privacy/check.sh` reads the title and the body. If it finds a home path,
  an email or another private text, the Board files nothing. The preview names each hit by its line, for
  example "body line 3: home path". Change that line and click **File the issue** again.
- When the issue is filed, the note leaves the list and `plugin-bugs.md`, and the pane shows a link to the new issue
  until you load the page again. If the Board files the issue but cannot change `plugin-bugs.md`, the note stays, and
  the preview says so. Then click **Dismiss**. If `gh` fails, the note stays, and the preview shows its error. Each
  note is filed only from its own preview. The other notes stay as they are.
- **Lint check** in Health counts the cards that landed with a lint command skipped because its tool is missing, as
  "2 unchecked". That command did not check their change. With no such card, the row does not show.
- **Test times** in Health warns when the last card test runs recorded no test times. Its next step says what
  **Record test times** does for your test command, and the button does it. Only an admin can use it. When the test
  command is one that setup knows a report for, it sets `test.report` in the pack to that report. When the test
  command runs only one test file, it wraps that command in `conveyor/tools/testtime.sh`. When the pack sets
  `test.fileCommand`, it wraps that command too. When the test command runs
  a script of your project, it files a held card with no GitHub issue. The card asks to wrap each test file's run
  in that script, because the script is yours. Release the card when you agree. When no plan applies, the row
  points to the section "Test file times" in `conveyor/README.md`.
- A Health row whose error is one line says what failed in a short sentence, for example "The Board could not get
  main from GitHub." Click **Raw error** to read the error as it came, with **Copy output** to copy it.
- **Work now**, at the foot of Health, shows what keeps the Conveyor machine busy now. Open it to read the machine.
  Each card's busy processes come first, grouped by card and step, the heaviest CPU first. Then come the busy
  processes that no card owns, such as another program or a stray test process. A closed card that still runs
  processes shows **closed: left over**, with the command that stops them. **Read again** reads the machine again.
  It is the same list as `conveyor.sh work`.
- The cache-write alert, which wakes the Foreman, shows where the cache writes of the last 24 hours came from. It
  names up to five card steps that wrote the most cache in that time, the largest first. Each shows the issue, the
  step (build, fix, rebase, review, judge or test), the model, and its 5-minute and 1-hour cache write tokens. A step
  shows only the tokens it wrote in those 24 hours. A Claude review or judge shows the tokens its card record gives,
  when the record is from those 24 hours. A step that has no record yet, such as one that still runs, shows
  as **(no step recorded)**. One more line shows the cache write tokens of those 24 hours that no card step accounts
  for, such as your own sessions.
  The alert shows what was written. It does not say that a write is waste.
- A blocked landing in the Fast lane shows its reason on one line. Its log is under **Show output**, as plain text,
  with **Copy output**.

## Set up a new repository

The first time the Board opens for a repository, a box asks you to set each project rule. Its title is
**Set up Conveyor for <owner/repo>**. It has five steps, and a bar at the top names each step:

1. **What to build**: Build issues, Never build and Split large issues.
2. **Landing**: Land as, Push on landing, Test before a push, Dependency guard, New issues start in and Whole
   suite in a card.
3. **Models**: Builder, Reviewer, Judge, Account and Review account.
4. **Limits**: Cards at once and Weekly pause.
5. **Your yes**: Approve visible changes.

Each rule shows its name, what it does and the controls of the Rules tab. The default is already selected, also when
the rule has another value now. To keep the default, click the selected choice or the **default: <value>** button.
The Judge's **May decline as a rare case** switches are not part of its default: a click on a selected switch turns
that level off.
A rule is set only when the build machine saves your choice. **Next** sets each rule of the step that is not set yet
to its default, then shows the next step. On the last step it is **Finish**. The footer says how many rules are set.

Each choice is saved when you click it. A model is saved when you pick it, with no **Save**. If you leave before the
end, the rules you set stay set.
**Later**, or Escape, closes the box until the next time the Board opens. While the repository is not set up, a line
at the top says **Conveyor is not set up for this repository yet**. Its **Set up** button opens the box again.

**Finish** records the setup in the project's control record. The box then stops opening. When a newer Conveyor has a
rule that you did not set, the box opens again with only the steps that hold the new rules.

The box does not ask for the machine's setting, Reserved cores: it belongs to the build machine. The test
command, the product paths and the owner stay with `/conveyor-belt:setup`.

## Rules

The **Rules** panel holds the settings. At its top, a line says when each change is saved. A line under it shows the
last change you made here, with **Undo**.

On the left are a search box and an index of six groups. Click a group to show its rules on the right. You change
each rule there, in its row. Type in the search box to find a rule in all the groups. The search reads the group
name, the rule name and the rule key. Only the rules that match show, and a group with no match hides. When no rule
matches, a line says so. The group you chose and the search text stay only while the page is open.

Each row shows the rule name, one short line on what it does, and its control. A choice of two or more values is
one control, and the value in force is the selected part.

1. **Models**: **Builder**, **Reviewer** and **Judge**, each a CLI installed on the loop's machine, then a model,
   then an effort ([Models](configuration.md#models)). The Judge is also On or Off. **May decline as a rare case**
   has one switch for each level, P0 to P3. Turn a level on to let the Judge decline a finding at that level as a rare
   case. **Always accept** lists the
   finding kinds the Judge accepts every time. **Account** and **Review account** pick the accounts
   ([Accounts](#accounts)). A seat is saved only when you press its **Save**. While a seat has a change that is not
   saved, the row shows the model in force.
2. **Capacity**: **Cards at once**. It counts every card on the belt, in any step, a card that
   waits too. A card that lands or pushes, or has landed or pushed, does not count. The machine's test slots limit
   tests. The On the belt figure gives the same count.
   **Weekly pause** is the usage at which no new card starts, with the usage now beside it. **Test files at once**
   is the most test files a parallel release suite runs together. The default is 2, and the next parallel run reads
   it. If the number is above the machine's test slots, the row says the suite runs at the slots
   ([Releases](releases.md#a-release-from-the-board)). On a devbox or a Linux box, the row says the suite machine's
   slots cap it. **Release suite mode** is how a release runs its test files when its press asks no other: **One by
   one** (the default) or **In parallel**. **Release suite runs on** is the machine a release's full suite runs on: **This machine** (the
   default), **Namespace Devbox** or **Linux box over ssh**. Card test steps stay on the build machine. A click on
   a choice saves it, and Undo puts the last one back. Only an admin changes it, because the release commit goes to
   that machine. On a devbox the row shows the Namespace login, the box to use, the size with its CPUs, what happens after a run, the
   box (its tag, or the devbox you named, and when a run last set it up, or "set-up time not kept" until a run has) and its tools.
   **Use** lists the devboxes of your account, which the check reads, and **A new box for Conveyor**. Pick a box you
   already have when your account is at its devbox limit, and the suite runs on that box. Pick **A new box for Conveyor**
   to run on a box that Conveyor leases by its tag, as before. The Board reads the login with a check when it shows the devbox. When you are not logged in, the
   row shows the command `devbox login` to run in a terminal on the build machine, and **Check the box** stays off.
   The Board reads the login again with each refresh, so the button comes on after you log in. For a Linux box, type
   the **ssh target** and the **Folder there**, then press **Use this box**. **Check the box** stays off while you
   edit the target and has not saved it. **Check the
   box** shows each line of `suite-machine check` with "ok" or "missing". For a devbox with a box named, the check reads
   the account's list and does not ask for a box. With no box named, an admin's check also asks the account for a box
   under the tag, which can create one; a member's check does not. A missing tool shows **Set up now**, which
   is off until Conveyor can run `.conveyor/test-machine.sh` from the Board
   ([Where the suite runs](releases.md#where-the-suite-runs)). **Stop a card's tests at the first failure** is On
   by default. On, a card's test step ends at its first failed case, and the step names the test files that did not
   run. Off, the step runs every case that it selects. A release and a main-red fix card run every case with either setting
   ([Which tests a card runs](configuration.md#which-tests-a-card-runs)). **Only the Test step runs tests** is Off
   by default. On, the rules that a card's sessions get do not tell them to run tests. The rules say that the Test
   step runs the tests, and that a session reads the result of the last Test step. A session cannot run a test
   command. Off, the sessions get the usual
   rules and run the tests of their change. **Reserved cores**
   shows the cores that card work does not use. You set them in the host file
   ([Reserved cores](configuration.md#cores-kept-for-you)). The row also links to the Tests page, which holds the test
   limits.
3. **Picking**: **Build issues** (the P0 to P3 switches and Follow-ups), **Never build** (area labels), **New issues
   start in**, **Dependency guard**, **Split large issues**, **Pick settings** and **Self-heals expiry** (the days an
   entry of the Self-heals list can go unfixed and unseen before it leaves the list). A main-red fix card is built
   whatever the P0 to P3 switches say, by design: held, every card that meets the red main would wait for good.
4. **Landing and push**: **Push on landing**, **Land as**, **Merge PR**, **Test before a push**, **Push after a
   combined test run**, **Lint check** and **Approve visible changes**.
5. **Done without asking**: **Requested fix**, **Review follow-up**, **Release check**, **Fixed block** and
   **Review retry**, each On or Off. Under them, the group **Cards with no GitHub issue** has **Tests page actions**,
   On or Off.
6. **Issue order**: **Held issues** shows the count. Click it to go to the held list. **Pinned issues** shows one
   row for each pinned issue, with its number and title. Conveyor picks them first, from top to bottom. Drag a row to
   a new place, or use its menu (**⋯**): **Move up**, **Move down** or **Unpin**. The first five pins show. **View
   remaining N pins** shows the others.

The other rules save when you change them. A setting changed there shows its new value at once. A value the host
refuses goes back, with the refusal beside it.

**Model prices** lists the price of each model the Board knows, in dollars per million tokens: input, output, cache
read and cache write. Each release updates the built-in prices. With no cache write price, a 5-minute cache write
costs 1.25 times the input price. A 1-hour cache write costs twice the input price.

- **Search** finds a model by its ID, its display name or one of its other IDs.
- **Seen but not priced** lists each model ID that this project's card sessions used in the last 30 days and that no
  model or alias prices, with its session count. **This is…** marks the ID as a known model: pick the model (the Board
  picks the likely one first). **Add as new model** opens Add model with the ID filled in. Needs you counts these
  models ([Models](configuration.md#models)).
- **Offered with no price** lists each model that a seat runs, or that the project's model list has
  ([Models](configuration.md#models)), and that no model
  or alias prices, with the seats that use it. It also lists each model that Needs you counts and that no other row
  shows, such as the Codex model that a family name (`sol`) runs. It has the same two buttons. Needs you counts these
  models too.
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
override" on its cost line. A step whose tokens could not be read in full can get an estimate
([Estimates and gaps](units.md#estimates-and-gaps)). The Board counts it with the priced steps, and puts `~` before
each cost that includes an estimate (`~$4.12`): the head tiles, Cost, Metrics, the Board's cards and its Today figure,
Landed, the Belt and a project's cost today. Metrics also tells how the estimate was made on the step's cost line. A step that gets no
estimate, because its model has no price or no step of its kind with an exact price ran on its model in the last 30
days, has no price.

**+ Add model** adds a model that the Board does not know: its ID as sessions report it, a display name, a provider,
and its prices. "Same price as…" copies the prices of a known model. An added model is priced like a built-in one, has
an "added" mark, and has **Remove**.

Other IDs (aliases) are for a model that comes back under another ID, for example through a proxy or another
provider (`anthropic/claude-sonnet-4-6`). A session with an alias is priced as its model and shows the model's display
name on the Board. A new display name does not change the model's ID.

Your prices, added models and aliases are saved in the pack (`prices` in `.conveyor/project.json`), so you commit them
with the project. Each change has Undo.

**Approve visible changes** is a switch per project, Off by default. On, a card whose change customers or staff
will see stops until its issue has a `Visible change approved:` line, or a parent issue that it inherits the yes from
(follow-ups and split slices) has one. Off, the tab says "off: visible changes land
without your yes".

**Land as** is **Main** or **Pull request**. Until you set it, it shows the pack's `push.landAs`. Main pushes the
landed cards to the default branch. Pull request pushes them to the branch `conveyor/landing`, and one pull request
from there collects them until you merge it. The tab then says "one pull request from conveyor/landing collects the
cards; merge it to close their issues" ([Land as](configuration.md#land-as)).

**Merge PR** is **Button**, **Release** or **Idle**. Until you set it, it shows the pack's `push.prMerge`. Button
leaves the merge to you, with **Merge** on the Control tab. Release merges the pull request when you make a release.
Idle merges it when no card is on the belt and no issue can be picked. When **Test before a push** or **Push after a
combined test run** is on, the test files
linked to its cards must pass first, when the pack can run one test file at a time ([Merge PR](configuration.md#merge-pr)).

**Test before a push** is a switch per project. On, before each push Conveyor runs the test files linked to the
landings since the last push, and a file that fails holds the push. Off, a push runs no test first, and the tab says
"off: a push runs no test first". While **Push after a combined test run** is on, its tests still run before each
push, and the tab says "off: Push after a combined test run is On, so its tests still run before each push". The switch shows the pack's `push.check` (on in a new project) until you change it
here. Your change goes in the control record and wins over the pack
([Which tests a card runs](configuration.md#which-tests-a-card-runs)).

**Push after a combined test run** is a switch per project, Off by default. Off, Conveyor pushes each card when it
lands. On, the cards that land wait until the combined run is due. Then Conveyor runs the tests on main, also when
**Test before a push** is off, and pushes the cards together when the tests pass. A file that fails holds every card,
and the push line names the landing that broke it. If the file failed before those landings too, the push line says
that and names no landing. While the switch is on, the tab says "on: the tests run even when
Test before a push is Off, and a file that fails holds every card". Below the switch, **After N landings** makes the
run due when that many landings are not pushed, and **At (UTC)** makes it due at a time of day. **Linked files** runs
the test files linked to the landings, and **All files** runs every test file of main
([Which tests a card runs](configuration.md#which-tests-a-card-runs)).

**Lint check** is a switch per project, On by default. On, the pack's lint commands run on each card's change before
its review and before its landing. Off, no lint command runs, and the tab says "off: no lint command runs, and cards
land with no lint check". Under the switch, the tab lists the pack's lint commands, each with the files it reads. You
cannot change them here: they are set in the `lint` field of `.conveyor/project.json` ([Lint](configuration.md#lint)).

**Split large issues** has three settings per project: Off, Shadow and On. On is the default for a new project. A project that set the rule keeps its setting. Shadow records what
the Judge would split a large issue into, and builds the issue whole. The tab says "shadow: the verdict is recorded,
and the issue is built whole". On files the slices as follow-ups and as sub-issues of the issue, and holds the issue
as their umbrella until all its slices are closed. Off checks no issue ([Split large issues](configuration.md#split-large-issues)).

**Pick settings** has three settings per project: Off, Shadow and On. Off is the default. Shadow and On record the
group of each card, the builder that the rule chooses for it, and the Judge's choice of seats. With Shadow, the card
builds on its builder as before, and the tab says "shadow: the pick is recorded, and the card builds on its builder
as before". With On, the card builds and is reviewed on the Judge's seats, and a card of an eligible group can build
on the group's challenger as a trial. A trial card is reviewed on the project's reviewer and judge. A seat that you set for a card always wins. With Shadow or On, the row shows
the three seats side by side under the setting (one under another on a narrow screen): **Builder**, **Reviewer** and
**Judge**. Each seat has a box with the models that it is set to now, and a table of the models that the Judge can give
the seat. In the table, choose the lowest and the highest effort of each model (**Any** for no limit), or click
**Remove** to take a model off the list. The **Add a model** menu under the table lists the other models that the seat
allows. One **Save** and one **Cancel** serve the three seats, and both are off until a seat changes, with "Unsaved
changes" beside them. **Save** sends each seat that changed, and no other. **Cancel** puts back the saved lists. If you
leave the tab, the changes stay until you save or cancel them. A seat with no model in its table shows **All models, any
effort**, and **Save** removes its list
([The judge's choice of seats](configuration.md#the-judges-choice-of-seats)). A
card shows its seats in one list ([Settings for one card](#settings-for-one-card)). The **Cost** panel then shows **Pick settings, by group and builder**: one row for each group and
builder, with its cards, the spend per landed card, the share of cards that landed with no retry, the review rounds
per landed card and the cards still open. The spend is all the steps of those cards, also the steps of the earlier
blocked, stopped and retried cards of the same issue. A card is still open when it is on the belt or blocked; a card
that you retried or stopped is not. When one of the steps has no price, the spend is "unknown" ([Pick settings](configuration.md#pick-settings)).

Beside that table, the **Cost** panel shows **Judge replay** for each project. It shows the last replay: how many
findings the replay judge ruled on as your judge did, each finding where the rulings are different, and the two
costs. Choose a model and an effort, then click **Estimate the cost**. The panel shows the estimate, and **Run the
replay**. Click it two times to start the replay. Only an admin can start a replay. The result shows in the panel when the replay ends ([Judge replay](configuration.md#judge-replay)).

The **Done without asking** rules turn each standing kind of yes on or off ([Standing yes](foreman.md#standing-yes)).
All are Off until you turn them on. **Review retry** On: the Foreman's watcher tries again each card
that its review blocked, and the Foreman gets no wake for it. A retry that fails still wakes the Foreman, with the
reason.

The group **Cards with no GitHub issue**, under **Done without asking**, has five switches, one per kind of card and
per project: **Tests page actions**, **Foreman orders**, **Review follow-ups**, **Release fix cards** and **Split
parts**. Each is Off by default. Off, that kind of card files a GitHub issue. On, it starts its card at once, with no
GitHub issue ([Cards with no GitHub issue](cards.md#cards-with-no-github-issue)). The first switch is described here: Off, an action on the Tests page that makes a card files a GitHub issue, and the belt
builds that issue as a card. The tab then says "off: an action on the Tests page files a GitHub issue, and the belt
builds that issue as a card". On, the action files no issue: it starts its card at once. The switch covers each such
action: Optimize, Rewrite as a direct check, Split it, Fix failures, Fix the waiting, Fix hollow cases, Make it run,
Make it run alone and Delete it. From a shell, `conveyor.sh control rules testissues=off` turns the switch On, and
`testissues=on` turns it Off. A project that set this switch when it was under **Picking** keeps its choice.

**Foreman orders** On: a change that you order the Foreman to make (`foreman.sh ask <project> card <title> <body>`)
starts a held card with no GitHub issue. Off, the command files an issue and holds it. **Review follow-ups** On: each
finding that a review files as a follow-up becomes a card with no GitHub issue, and the card names its parent. Off,
each finding is filed as an issue. **Release fix cards** On: the fix card of a red release suite starts with no GitHub
issue, and the suite starts again once each fix card has landed and its change is in the commit the suite tests. Off, it is an issue. **Split parts** On: the parts of a split issue
are cards with no GitHub issue under the umbrella issue. Off, they are issues. From a shell, the switches are
`conveyor.sh control rules foremanissues=off`, `followupissues=off`, `releaseissues=off` and `splitissues=off`. As
for **Tests page actions**, `off` turns the kind On, and `on` turns it Off.

A card with no GitHub issue builds, is reviewed, is tested and lands as other cards do
([Cards with no GitHub issue](cards.md#cards-with-no-github-issue)). In **Landed today**, its row keeps its title, its
steps and its result, and **Card text** shows the text that it came from. **File on GitHub** files an issue with the
title and text of the card. Conveyor closes that issue at once with a comment that names the commit, because the work
is already on main. The row then links the issue. A card that shows **Already fixed** landed no commit, so its row has
no **File on GitHub**.

## Held issues and dependencies

An issue that is not being built is in Held for one of four reasons: **Held by you**, **Held by a label**,
**Skipped by a rule** or **Waiting on #N**. "What these mean", under the Held heading, says where to change each.
With the rule **Push on landing** off, an open issue whose card landed is not work to build. The Rules tab shows it
as **Landed, not pushed**, and the count of open issues names it apart. "Holds keep N issues back" does not count
it, and the row of its parent issue shows it as landed. The push closes it.
After **Queue** or **Queue all**, the row says "Queued: this shows in about a minute." until the next snapshot has it. A row
that you queued by removing its label says "Label removed: it goes into the queue in about a minute." instead. If
the host refuses, the row shows the reason.
An issue that someone outside the project opened shows **Opened by someone outside the project: release it to build
it** in place of **Held by you** ([The control record](configuration.md#the-control-record)).

An issue that [Split large issues](configuration.md#split-large-issues) split is the umbrella of its slices. It stays
in Held until each slice lands, and then Conveyor closes it. Its card says "Split into #a, #b; closes when they land"
and lists each slice with its state: landed, building, blocked, waiting or held. The umbrella has no **Queue**, and
a drag to Queue does not release it: queue its slices, which keep their own **Queue**. An issue that waits on an umbrella says so, as "Waiting on #12 (its slices
#20, #21)". When the slices are cards with no GitHub issue, the umbrella shows "Held as the umbrella of a split: waits
for <card ids>" in place of **Held by you**, and has no **Queue**. A shut slice has "(shut)" after its id. Its card is
in the group of its closed card, not in **Held by you**, and the Rules tab does not list it as held by you. When each
slice has landed, it says "each slice landed; the loop closes it at its next turn".

On the Rules tab, "waiting on another card" opens the waiting list. It shows each waiting card with the cards it waits
on, as "waits on #12 (testing), #13 (landed)". The **Dependency guard** row sets the guard On or Off. With it Off,
each card of the waiting list has **Queue anyway**, which asks once and then sends `control force`.

Each card in the Held and Queue columns has **Depends on…**: type or pick open issues, or remove one (×). The host
writes the issue's `Depends on: #N` line on GitHub (`conveyor.sh control depends`). It refuses a self-dependency, an
issue that is not open, a cycle, or an issue whose card already runs.

## Settings for one card

Each card in the Held, Queue, Building, Review and Needs you columns shows the builder, reviewer and judge that it
runs on, one row for each seat. A row shows the seat name, the model and effort (for example
"claude-opus-5-5 · high"), and who chose the seat:

- **this card**: you set the seat for the card. Your setting always wins.
- **Judge's pick**: the rule Pick settings is On and the Judge chose the seat.
- **trial**: the card is a trial, and builds on the group's challenger.
- **promoted**: the seat is a challenger or a seat that you promoted.
- **project's**: the project's seat. When the Judge's pick failed, or the weekly limit guard stopped it, a box under
  the list says why the card runs on the project's seats.

When the rule picked the card, a box under each row, labelled **Why the Judge chose it**, shows the Judge's reason
for the seat. When a limit of the pack changed the seat, the box says what changed. When the card does not run on
the Judge's seat, the box names the seat that the Judge chose.

A landed card, or a card of another project, that the rule picked shows the same list, with no buttons. You can
change a blocked card's settings before you retry it.

- **Settings** opens a group for each seat: the seat name, its model list, and an effort list labelled **Effort**.
  Pick **Project's** to use the project's seat. The effort list shows only once you pick another model. Until then
  the line says "the project's effort".
  The lists show only the models that the pack allows the seat. **Save** sends each changed seat
  (`conveyor.sh control card`).
- **Pick for me** asks the project's judge to choose the three seats for the issue. The card shows the judge's model,
  effort and reason for each seat. Nothing changes until you press **Apply**. **Discard** drops the choice.

A step that already runs keeps its settings. The next step uses the new ones. [Configuration](configuration.md#settings-for-one-card)
tells more.

## Push landed and Run full test suite

The Rules tab's **Push on landing** rule is Off by default. Conveyor lands each card on main and pushes when you
press **Push landed** or **Push now**. Turn the rule On, and Conveyor pushes each card on its own after it lands.
With **Push after a combined test run** On too, it pushes the cards together after their combined test run passes.

With the rule Off, a card that landed leaves the belt. It is not in On the belt, Belt 3D or `/units` ON THE BELT. Landed
today shows it as "Landed, waiting for Push landed", and the Control tab counts it in "N landed, not pushed". Its Push
step stays to come until you press Push landed or Push now. With the rule On, a landed card stays on the belt as
"pushing" until Conveyor pushes it.

**Push landed** and **Run full test suite** are on the Control tab, which shows "N landed, not pushed". Push landed runs
the project's full test suite, the `test.full` of the pack (the project's settings, `.conveyor/project.json`), on main.
Setup sets `test.full` to your test command in a new pack. Green, it pushes the landed commits that the run tested. Red,
it runs each failed case alone and judges it. Only an engine case or a case of a node test file runs by itself: a Python
or other shell test file runs whole, and after a suite that timed out the whole suite runs. A case that passes alone
goes on the flaky-test record. A case that fails in the code becomes a P1 fix card. A case that fails for the machine or
the network is declined, with its reason. When each failed case passes alone, Push landed pushes, and the result says
"Flaky". Else it pushes nothing. **Push anyway**, beside a red result, pushes those commits after a confirm. **Run full
test suite** runs the suite and pushes nothing. A project with no `test.full` shows both buttons greyed
(`conveyor/README.md`, The full test suite).

Push landed, Run full test suite and Release share their results for each commit. When one of them passed on the
commit, the next runs no test: Push landed pushes at once, and the result says "Reused the green run of <time> on
<commit>". After a run on an earlier commit, the files that failed there run again, and so do the files that the
commits since then add or change, and the files that `test.command` picks for those changes. The result says "Reran 1
file, reused 2 passed files from <commit>". A change to the `test` settings of the pack, or to a file that its test
commands name, runs the whole suite ([Releases](releases.md)).

**Push now**, beside Push landed, pushes the landed commits at once, with no full test run. Click it, then click again.
It pushes main as Conveyor does after each card when the rule is On: through the project's pre-push hook only. If the
hook fails, nothing is pushed and the card shows in Needs you with the failed check. It is greyed while a full test
run is under way, or when nothing waits for a push. Use Push now for a small change that the card's own tests and the
pre-push hook cover. Use Push landed when you want the whole suite to run before the push: it pushes when
the suite is green, or when each failed case passes alone.

Under the buttons, the Board shows the push. While it runs: the commit, what runs ("Tests before the push running",
"Getting the push ready (worktree, dependencies, test slot)", "Pre-push hook running", "Push running with no pre-push
hook", "git push ended, finishing the push", or "Pushed, waiting for GitHub") and since when, its process, the time it
has run and the newest line of the pre-push hook's output. Below that are the cards in the push and when the push
started, with the time since then, also for a hook that writes nothing. A push whose process is gone and that did not end shows as
stale, with the path of its log. After the push: passed, or failed with the failed test and the path of its log, or
"started no push" and why; and "Main is still N commits ahead of the remote" when it is. Each push has its own log in
the state folder ([Push](cards.md#push)).

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
tag, and one status. The status is the first of these that applies: Suite failed or Suite passed while the run makes
the coverage map, Suite running, Drafting notes, Suite failed, Main moved since the suite, Notes card under way,
Released, Notes missing, Suite not run, Ready to release.

Under the top row are three numbered steps. Each step has a mark: done, failed, in progress or to do.

1. **Release notes**: `docs/releases/<version>.md` on `main`, "written" or "missing: Draft notes writes them". While
   a card adds the notes draft to `main`, the step is in progress and names the card. A line under it says that the
   suite runs by itself once the card's commit is on the branch the suite tests and no other card is open, and then the
   release when the run was started as a release. A push or a merge can hold that commit (step 2 of "To release from
   the panel"), and a card still open delays the suite. When the card is closed before it lands, the step shows it
   failed and names the card: click **Draft notes** again.
2. **Full suite**: the whole suite on the head of `main`. It shows passed or failed, with the commit and the time, or
   "Not run". When the suite ended and the run makes the coverage map, the step shows passed or failed with the
   commit, and its failed test files, and says that the run makes the coverage map. **Stop** still shows, and stops
   only the map: the suite's result stays. **Release** and **Release anyway** wait until the map is made. While the suite runs, a bar shows the test files done of all the test files, with the names of the files
   that failed. A test case that ran out of time shows as "<case>: timed out". When release-prep runs the failed
   cases again, one at a time, the step says which round runs now, of how many, and for which case, with when it last
   moved. The bar then shows that round's test files. Under it, a "First run:" heading shows. Below the heading are the number of test
   files done and failed, and the names of the failed files. When the run under way, or the last run,
   runs test files, the step says how: one by one or in parallel. A **Release** that uses the suite that passed or
   failed before shows the mode of that suite. It says no mode for a run that runs no test files and keeps the
   passes of an earlier run, on the same commit or an earlier one. A run that runs only some files again, and keeps
   the passes of the other files, shows its mode. A full test run in progress shows here too. When **Release** is
   enabled, the step also says what it does: "Uses the suite that passed at <time> on <commit>", or "Runs the suite
   first (about N min)". When the suite failed and fix cards were filed for it (see `docs/releases.md`), the step says
   how many of them have landed, and lists each fix card with its issue link and its state: open, landed, or closed with no landed card. One line under them
   says what happens next: "The suite runs again when every fix has landed"; when every fix has landed, that the
   suite runs again when their commits are on the branch it tests and no other card is open; "The suite runs again
   now" when Conveyor has started it; or, when a fix card was closed with no landed card, that the release waits for
   the Foreman.
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

When the button runs the suite, the second click asks "Run the test files one by one or in parallel?". This applies to
**Run suite**, **Run suite again**, **Run again on the new main**, and **Release** when it runs the suite first. Click
one of the two choices, or **Cancel**:

- **One by one**: slower, with the least load on the build machine. Conveyor adds `--serial` to the command.
- **In parallel**: faster, with more load on the build machine. The belt is slower while the suite runs. Conveyor adds
  `--parallel` to the command.

When the chosen machine is the devbox or the ssh box of the rule, the two lines name that box in place of the build
machine, and **In parallel** does not say that the belt is slower.

The choice that matches the rule **Release suite mode** (Rules tab, Capacity) is pressed already and says "The rule's
choice". **Draft notes** asks nothing and sends no mode: it runs no suite itself, so step 2 shows no mode for it. A
suite that starts with no mode given uses the rule's mode. This includes the suite that runs after the notes card's commit is on the branch the suite tests and no other card is open.

When the project's rule sends the suite to another machine (a Namespace Devbox or a Linux box over ssh; see
[Where the suite runs](releases.md#where-the-suite-runs)), the question also asks "On which machine?". The two choices
are **This machine** (the belt is slower meanwhile) and the machine of the rule, with "the rule's choice" and, when the
newest run was on that machine, when it ended. The rule's machine is the one chosen at first, and the chosen one shows
in a frame. A click on **This machine** makes Conveyor add `--machine local` to the command, for that one run. With the
rule on this machine, the question has no machine part.

While a run goes on a devbox or a box over ssh, step 2 shows a line with the machine, the box (the lease of a devbox,
the address of an ssh box), the commit and when the lease began. Under it are the steps of that machine, each a chip:
**Start** (with "reused" or its time), **Set up** (with "not needed" or its time), **Check out**, **Run**, **Make the
coverage map** (only when the run makes one), **Bring back results** and **Give back the box**. A finished step is green, the step now is blue. A run on this machine shows no
such line and no chips.

When the machine fails to start, set up or check out, no test runs. The status is Suite not started. The chip of the
failed step says why, for example "Start · not logged in to Namespace". One line says what to do. For a login, it says
to run `devbox login` once in a terminal on the build machine, then click **Run suite again**. Two buttons show:
**Run on this machine instead**, which runs the suite on this machine for that one time, and **Run suite again**. The
suite never moves to another machine by itself. When it is this machine that fails (its worktree cannot be made), the
reason shows as a line, and only **Run suite again** shows.

To release from the panel:

1. Make sure that the field has the version to release.
2. If **Release** says "needs release notes docs/releases/<version>.md", click **Draft notes**. Conveyor writes a
   draft and starts a card that adds it to `main`. When the card's commit is in the commit the suite tests, the suite
   runs by itself, when no other card is open. With **Push on landing** Off, that is after you press **Push landed** or **Push now**. With
   **Land as** Pull request and **Merge PR** Button, that is after you click **Merge**. If the draft breaks the notes
   style, the run stops and step 1 shows why: edit the draft, then commit it to `main`.
3. If **Release** says "needs the whole suite to succeed on main's head (<commit>)", click **Run suite**.
4. Wait for the suite. While it runs, **Release** says "the suite is running (N of M files)". If it fails, **Release**
   says "the suite failed: <count> failures". Fix the failures, then run the suite again.
5. When the notes are on `main` and the suite passed on the head of `main`, **Release** is enabled. Click it, then
   click again. A **Run full test suite** that passed on the head of `main` also counts: step 2 says "The full test
   suite passed on <commit>", and the release uses that pass.

**Release** is disabled until it can run. Its text says what it waits for. For a version that is released already, it
says "v<version> is already released".

- **Draft notes**, **Run suite**, **Run suite again** and **Run again on the new main** run `conveyor.sh release-run prep <version>`. Conveyor
  runs `conveyor.sh release-prep <version>` and nothing more. If `main` has no notes for the version, it writes a draft
  of them. A draft in the notes style goes to `main` as a card with no GitHub issue, and the run waits for it. When the
  card has landed, its commit is in the commit the suite tests and no other card is open, Conveyor runs `conveyor.sh release-prep <version>`
  again, with the same mode and machine, and that run runs the suite. A push still owed holds it, and so does an open
  pull request of Land as `pr` with Merge PR `button` or `idle`, until it is merged. A draft that breaks the notes style stops the run. Else it runs the suite on the head of `main`: the whole suite, or only some of its files
  ([Releases](releases.md)). An earlier suite run is a release's, a Run full test
  suite's or a Push landed's. When one of them passed on that same commit, no test runs. Step 2 says which: "Reused
  the green run of <time> on <commit>", "Reran 1 file, reused 2 passed files from <commit>" or "Ran the whole suite".
  These buttons do not release.
- **Release** with the version runs `conveyor.sh release-run <version>`. The second click is your yes to the release.
  When the suite of that version passed on the head of `main`, and `main` did not move after it, Conveyor uses that
  pass and runs `conveyor.sh release <version>` ([Releases](releases.md)). Else Conveyor runs
  `conveyor.sh release-prep <version>`, which runs the whole suite first, and runs `conveyor.sh release <version>` when
  the suite passes. The second click's text says which of the two occurs. Nothing else starts a release.
- **Release anyway** shows beside a failed suite on the head of `main`. A release that was refused after that failed
  suite keeps it: step 2 still shows the suite as failed, with its mode. The first click shows the failed files and
  cases. The second click is your yes to release over them: Conveyor runs `conveyor.sh release-run anyway <version>`,
  and the release names you and the failures. The status of the suite stays failed
  ([A release over a failed suite](releases.md#a-release-over-a-failed-suite)).

**Stop** shows while a run is in progress, and while a run waits for its notes card or for other open cards. During a
run, a second click stops the processes of that run. Conveyor itself continues. During a run on a devbox, the line
beside it says that Stop stops the run on the devbox and gives the box back.

While a run waits, **Stop** shows in the notes step. After a second click, the run does not start again when the card
lands. If the run started again before the click arrived, Conveyor stops nothing and the panel shows the reason. The card is not closed and can still land: `conveyor.sh shut` closes it.

When a card lands while the suite runs, the status stays Suite running, and the suite step says that `main` moved. The
two buttons stay disabled until the suite ends. Then the status is Main moved since the suite, and the button is **Run again
on the new main**. The run does not start again by itself.

**Show N changes** opens the changes on `main` since the tag, newest first, 10 at a time. Each change is one line: the
issue number, as a link, and the issue title.

## Card steps

- A finished review reads "Review 2: passed" or "Review 2: changes asked". A review the judge read says "judge: N
  accepted, M declined". The bar of a review step is named only "Review 2". The verdict, the count of findings and the
  judge's counts are on one line under the bar. Each finding has an id, E1, E2 and so on, that it keeps from one review
  to the next. A finding that came back after its fix says so, for example "E2 came back after 2 fix rounds".
- Under a review's bar, its findings are one list, one row each, in the order the reviewer gave them. A finding that
  the judge declined is in the list too: its row is dimmed and has a **Declined** mark, and under it a block, **Why the
  judge declined it**, gives the judge's reason. A row shows the
  priority (P0 to P3), the finding, and under it the file and line. Click **Proof** to read the reviewer's proof. Click
  **Reviewed lines** to read the lines that the finding names, as that review read them. When the finding names lines
  that the change or a fix round deleted, you also see the deleted lines. These lines stay after the card's worktree is removed. The
  file link goes to main, which can show different code. **Show output** on a review step shows the review's text as
  plain text, closed until you open it. Each other step's output shows as plain text, with its failures first.
  **Copy output** copies the output as plain text, for a review too. This is the same in On the belt, Landed today and
  Needs you.
- A fix session shows what started it: **Fix 2: review findings**, **Fix 1: reply check**, **Fix 3: main changed under it**,
  **Fix 4: tests failed** or **Fix 5: lint findings**. Hover over the label for the full reason. The number is the
  Fix round that the Fix step shows. A fix and the lint fix before the review after it have the same number. A lint fix
  before the landing starts a new Fix round, so it has the next number.
- A reply-check fix after the build shows on the Build step, "Build · reply check fix" and then "Build · reply check
  fixed". The Fix step shows the other fixes.
- A lint fix before a review, after the build, also shows on the Build step: "Build · lint fix" while it runs, then
  "Build · lint fixed". A lint fix before the landing, or before a review after a fix, is a Fix step: "Fix 2: lint
  findings". A lint fix before a review after a rebuild shows on the Land step: "Land · lint fix"
  ([Lint](configuration.md#lint)).
- Each lint check shows in the card's steps as **lint**, with a row for each command under it: a short name (the
  script's file name, such as `lint-shell.sh`; the size check as "Size, limit 800 lines"; for an inline command, its
  first program after a guard, such as `ruff`), a chip for its result (Pass, No files, "Findings: 2 of this change",
  Error, or "Skipped: missing <tool>" when its tool is missing) and its seconds. "Findings: 0 of this change" is grey,
  not red: the command found problems only on lines the change did not touch, and the step passed. Hover over the name, or focus it, to see
  the whole command; "Show command" shows it on a touch screen. A command with findings of this change, or an error,
  comes first, with its findings (file, line and text, all of them) or its error under the row. When the change changed
  a trigger of a command that ran, the rows end with "Tools ran as installed". A lint check recorded without its
  commands shows its reason as one line: each command's result and seconds.
- A card in its Test step shows how many tests have run, "142 of 205 tests", and " · 2 failed" when any failed. A test
  command gives the count when it prints `TESTRUN cases=N`, and names each case as it ends with an empty file in
  `cases/ok` or `cases/failed` of its test log folder (`conveyor/README.md`, The test step). With no case count, the
  card shows its test files, "3 of 6 test files". Each test file counts once. If the run ran more test files than it
  selected, the card shows the extra files after the count, "86 of 86 test files · 15 more files than selected". The
  text starts with the list that the run got: "changed: 7 files" ([Which tests a card runs](configuration.md#which-tests-a-card-runs)).
- A bug card shows "Proof run" on the Build step while its new tests run on main without its fix, with its test files
  run, "297 of 1161 test files". While all the test slots are in use, it shows "waiting for a test slot". No review
  runs then.

## Tests page

The Tests tab shows, from top to bottom: the Test map, the
figures, the table of test files, Test edits by cards, Removed by Optimize, and Recent actions. The settings of the
tests are in the Test settings panel, after the Tests panel on the same tab.

The Test map part shows the state of the [test map](configuration.md#the-test-map). A made map shows how many source
files and test files it maps, how many commits it is behind main, when it was made and how long its run took. It
also shows how many test files the map could not map. A folded list gives each of these files with the reason. The
map does not use these files to pick the tests of a card. The other states are "Not made yet", "Off" and "Failed", with the reason. An admin can click **Build the test map** to
make the map now. Before you click, the part names the coverage tool and the time of the last whole-suite run. The
build runs your whole suite once on the build machine, on a test slot. While it runs, a bar shows how many test files
have run, and **Stop** ends the build. When the build ends, the part shows its result. The Board refuses the button to
a member. When the map is off, when `test.map` names a map that your project keeps itself, or when your language has no coverage tool, the part tells you and shows no button.

"Test history starts at" in the Test settings sets a UTC time, such as `2026-11-21T00:00:00Z`. The page counts only the
runs, failed steps and flaky entries on or after it: the table, the figures (with the slot wait and run time of the
card Test steps), the whole-suite run, the Fix failures and Fix the waiting drafts, the test rules, and the facts that
Judge gives the Tests model. It deletes nothing. Older runs stay on record,
and an empty value counts every run again. A change is saved in the control record
(`conveyor.sh test-settings history-start`). Use it after a change of machine or of test command, when the old runs no
longer say how fast the tests are.

The figures count the timed files, the files slower than usual and the files that wait more than they work, and give
the slot wait and run time of the card Test steps of 7 days. No test file has a CPU budget. Click the figure of files
slower than usual or that wait, and the table shows those files only, as their filter chip does.

The table shows every test file of the project: each file's CPU seconds, its median, its last runs, the clock time of
its newest run (Last run took; point at it to see when that run was) and its status (Slower than usual, Waits,
Flaky and others). A file with an issue shows a link to it, "#NN". The runs are those of card Test steps and of
whole-suite runs (Run full test suite, Push landed, and the suite of a release), and the times the test-speed survey
saved in `.conveyor/test-times.json`. A file with no time yet shows
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
helper. Click **Save the test command** to save it in the pack's `test.command`. Conveyor also wraps the pack's
`test.fileCommand`, the command a card runs each test file with, when it is one plain command. Only an admin can save it. The next
run of the file records its CPU seconds, and Wall only goes away. In all other cases the row says why no action can
apply, and shows none. Then wrap each test file's run with the helper in your test script (`conveyor/README.md`, Test
file times).

A Whole suite only file costs more than its own time. A card's Test step never runs it, so a change to it is tested
only by a whole-suite run. The status gives the CPU seconds of the newest whole-suite run on record. To fix it, open
its row and click **Make it run alone**. The issue asks a card to make the file run by itself, or to move what it runs
into test files that the runner can list, and to keep what it tests. Before the card goes to review, Conveyor checks
two things. The pack must no longer mark the file `wholeOnly`. The file must pass when it runs alone with the change,
on a test slot, through the pack's `test.fileCommand`. When the change removes
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
that model. When the check still finds a hollow case that the issue names or that the card adds or changes, or a
deleted case has no COVERED-BY line, the card is blocked, and the reason names the cases. A hollow case in another
part of the file does not block the card. It goes to the Declined list of the card. The file stops showing Hollow when a later run of Judge names no hollow case.

A file shows "Waits" when its last run took more than 2 times its CPU seconds on the clock. The file waits more than
it works: it sleeps, polls, or waits for a timeout, a lock or the network. Judge reads the clock and CPU seconds of
its recent runs and names each wait on a line `WAIT: <case> | <kind> | <file:line> | <reason>`. To fix the file, open
its row and click **Fix the waiting**. The issue holds the clock and CPU seconds of its recent runs and the waits that
Judge named. It asks a card to remove or shorten the waits and keep what the cases test. Before the card goes to
review, Conveyor runs the file alone 3 times in a row with the change, each run on a test slot. Each run must pass
and take at most 2 times its CPU seconds on the clock. When a run does not, the card is blocked, and the reason names
that run.

A test must check what it protects directly. Some files check it through a proxy: they run other test files or the
suite runner, run the real loop, or wait for a real process with a poll such as `wait_until`. Judge says what a file
protects and how it checks it. For a proxy, the verdict is indirect, and Judge names each proxy part on a line
`DIRECT: <what it protects> | <the direct check> | <the cases that must keep passing>`. The cases are the text
after the last `|` of the line. A DIRECT line keeps only the cases that the file has. The record lists the other
names as dropped. With that verdict,
**Rewrite as a direct check** is the step that the Board suggests. A Whole suite only file does not get it, because
the check of the card runs the file alone: make it run alone first. The button opens the issue preview, with the title
"Rewrite the test file <file> as direct checks" and the DIRECT lines in its text. A `|` inside a field shows as
`/`. You can edit both before you file it. The text keeps every DIRECT line and the line of the last runs. When they
do not all fit in one issue, the button opens no preview, and the line under it says why. When a new "Test history
starts at" counts more runs and the text then does not fit, the open preview closes, and the line says why. Conveyor checks the card as an Optimize card. The change must keep the
file and each case that a DIRECT line names and the file had before the change, and add or remove no other test
file. The check skips a name that is not a case of the file. When it drops one of those cases, the card is blocked, and the reason
names the case. The file must also pass alone with the change, in fewer CPU seconds than its last runs.

Conveyor also finds proxy checks with no model and no test run: it reads each test file of the default branch. A line
that starts another test file or the suite runner is a proxy check. The suite runner is the pack's `test.command` or
`test.full`, `.conveyor/test-full.sh`, or the suite runner of the Conveyor engine, and a test file is a path with `.test.` in its name. A line that calls a poll helper is a proxy check too. The poll helpers are in the pack's `test.pollHelpers`
(`wait_until` when it is not set). The row of such a file shows the chip "Proxy checks" with the line numbers. Point
at the chip to see the text of each line. Next to the chip, each line says what it does and gives the comment that
says why: the comment at the end of the line, or the comment lines just above it. When there is no such comment, the
line says so. Click the "Proxy checks N" filter chip to see only these files. A command that is only text in a
heredoc can also show as a proxy check.

A file with no run on record shows "Never run". A file whose runs are all before the test history start ran, so it
does not show "Never run". When Conveyor can tell why, the status says it: the pack's
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
**Make it run** and **Delete it** (on a file Never run), **Make it run alone** (on a Whole suite only file), **Rewrite as a direct check** (when the verdict is indirect, on a file that is not Whole suite only), **Split it**
(when the newest verdict is split, on a file that is not Whole suite only), Run and More. The step that the Board suggests is the primary
button. Six tiles follow: the CPU seconds now with the median, the last 4 runs as bars, the last Optimize as a
percentage with its issue and its CPU seconds before → after, the clock time with its clock / CPU ratio, the bugs
caught and the mutants caught (or "not checked"). Point at a bar, or move the keyboard focus to it, to see its CPU
seconds. The failures of the file come next, when it has any. Last, the 3 latest events, with a button that opens
the Timeline.

The Timeline lists every event of the file, newest first: its runs (each with its card's issue, "whole suite" and
its result, or "test-speed survey"), its Optimize issues, the test edits of landed cards and the runs of Judge. The filter chips All, Runs,
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
Mutation check, Split it, Keep a case off, Close its issue as done and Mark as slow on purpose
(`conveyor.sh test-settings`). Use the arrow keys to move in the More menu, and Escape to close it.

An issue that you file from the Tests page goes to the queue. When the Rules tab's New issues start in is Held, the
issue is held. `conveyor.sh testissue <test file> <title> <body>` files the same issue from a shell. When a Foreman
session runs it, the issue is held too, and the command says so.

When the Rules tab's **Tests page actions** (under **Cards with no GitHub issue**) is On, these buttons show no preview
and file no issue. A click starts the card at once, with the title and text that the preview would show, and the row
says "Card queued with no GitHub issue". Optimize on the selected files does the same for each file. The loop picks
such a card before the queue. On the belt the card shows as "Tests page: <file>", with its title. `conveyor.sh
testissue` does the same when the switch is On, also while New issues start in is Held: you asked for the card. For a
Foreman session it files no issue either, but the card starts held, and the command says so. The card waits for your
yes: `conveyor.sh control release <card id>` releases it.

Split it shows the issue first, with the title "Split the test file <file>". Its text asks for two or more test files
of the same area, with each case kept once and unchanged, each new file under 600 lines, and
`.conveyor/engine-areas.json` and the test map updated. When the newest verdict of Judge is split, the text also gives
the reason of Judge. Edit it, then click "File this issue". On a Whole suite only file, Split it is disabled: the file
runs other test files, so split one of those. The reason shows under the menu, and the arrow keys still reach the item. When the newest verdict is split, Split it is a button of the row and
not in More.

Explain the slowdown gives the model the file's recorded times and the window where its time went up: from the last
run at its usual time to the first slower run. The model gets each commit made in that window that changed the test
file, a file that the test map links to the test file, or a file that the map shares with most tests (such as a shared
test helper). When a card's test step is the first slower run, the commit that landed that card is in the list too,
if it changed one of these files. Commits that changed only other files are not in the list. For each commit, the
model gets its card and issue, its time, its subject, its changed files with their line counts, and its diff of these
files. The commit of the card of the first slower run comes first. The other commits come oldest first. When no such
commit was made in the window, the facts say so. The model must weigh every commit in the window. It must not blame
a card only because that card's run was the first slower one. The model cannot run git. When the diffs are too long,
the model gets their start and a note that says which lines and files are left out. All times are in the time zone
of your browser, on the clock that is set in **Time** in Customize when you click Explain the slowdown.

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

The Timeline lists each Optimize issue filed for the file, each older "Speed up the test file" issue, and each card
that an action on the Tests page started for the file with no GitHub issue. Each shows its link and its state: open,
building, blocked (with the reason), landed (with the commit), or closed without landing. A card with no issue shows
"No issue" in place of the link. A landed issue or card also shows the fix of its card (sped up, split, merged into a
file, or deleted), the CPU seconds of the file before → after the fix with the change as a percentage, and "Helped" or
"Did not help". When the file ran since the fix landed, it also shows the median CPU seconds of those runs. The first
run after the fix has a mark in the table's Last runs and in the Timeline, while the row still shows that run. When a
mutation check of the file ended before the fix landed and another ended after it, a landed issue or card also shows
the mutants caught before and after ("Mutants caught before: 9 / 20, after: 14 / 20").

Test edits by cards shows what each landed card did to a test file that the project already had, newest first. A
new test file is not in it. Each entry shows the issue of the card, the file, when the card landed and the counts:
assertions removed, expected values changed in kept assertions, skip, only or todo marks added, timeouts raised and
cases deleted. Conveyor reads shell test files and JavaScript and TypeScript test files. A file of another kind shows
"Edited, not read". The Weakened filter, which shows first, shows the edits with one of these counts above zero. All
edits shows every edit. Weakened edits on many cards show a pattern: tests that were made weaker to get green. The
Timeline of an open row lists the edits of its own file.

A file that an Optimize deleted, or merged into another file, is not in the table. "Removed by Optimize", below the
table, shows it with its last numbers, its issue ("No issue" for a card with no GitHub issue) and the test files
that now have its cases. For a deleted file,
these are the test files that the review of its card named.

Recent actions is closed until you open it. Its heading shows how many actions run and how many are queued. It lists
the test actions, the Optimize issues and the cards with no GitHub issue, newest first, each with its state. A card
with no issue shows "No issue" in place of the issue link. Click a file name in it to open the row of that file. The name of a file that Optimize removed is plain text, as that
file has no row.

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
not need a test that fails on main. The card must do what the judge's verdict in the issue asks. A file it keeps must
pass in fewer CPU seconds than the median of the last runs that the issue lists, else the card is blocked with a reason
that names the verdict and both numbers (`conveyor/README.md`, Bug cards: the new tests fail without the fix). For the
verdict stabilise, the file may cost as much as those runs, and the build's reply must name the cause of each flaky
case and how the change removes it. For the verdict merge, a file that takes in another test file runs with the
change, together with each other test file that the change keeps. These files may cost as much as they cost without
the change, run with the test files that the change removes. When the file goes into another test file, that file must pass with the change
and may cost as much as it did without the change plus the median of the last runs of the file it takes in, else the
card is blocked with a reason that names the failure or both numbers. Each file of a split must pass, and the files' CPU seconds summed must be at most the old file's plus a
start-up allowance for each new file. For a delete or a merge, the review names the
test that still covers each case of the file. Each file of an action on many files gets its own action or issue, and
its own answer. At most 3 test actions run at once. The others wait as queued and start in the order asked. Stop
takes a queued one off before it starts.

The Test settings panel, on the Tests tab after the Tests panel, has four sections. Each section says once where its
settings are saved:

- **Test actions**: "Model for Tests actions", the CLI, model and effort that Judge and Explain the slowdown use. It
  is saved in the control record. "In force" shows the saved model only while you have a change that is not saved.
- **Test limits**: the files slow on purpose, and "Take a file off card runs" when the pack has it. They are saved in
  the pack file.
- **Test history**: "Test history starts at", saved in the control record (see [Tests page](#tests-page)).
- **Auto-file**: the switch for the test rules (`conveyor.sh testrules`), their guards and their fields, saved in the
  pack file. The preview of what the rules matched is under the switch, and the log of what they filed is at the end.
  Each is in a box of its own (`conveyor/README.md`, Test actions).

## Benchmarks tab

The Benchmarks tab shows the [SWE-bench Verified](benchmarks.md) runs of the project and their arms. A row of buttons
at its top opens its seven pages: **Scoreboard**, **Versions**, **Compare**, **Live run**, **Task**, **Task map** and
**Plan a run**. Each page starts with the question that it answers, then a verdict: one sentence that answers the
question from the figures, and the reason. The tab reads the runs from the build machine when you open it, and again
when a run moves on. Only an admin can start, stop, check, archive or delete a run. The Board refuses these buttons to
a member. The answer to **Archive**, **Restore** and **Delete** shows in the run history, and stays there until you
click again. A refusal of **Start the run** or **Check the arms first** shows under the two buttons. **Stop the run**
shows no answer when it works, and shows a refusal beside the button.

Two pages load what they show with no click: the commits on **Versions** and the readings on **Compare**. Each comes
from `bench swe diff`, which calls the model for each flipped task that has no saved reading. So the page asks for
the diff of a pair of results once while the Board is open. A redraw, or a return to the page, uses the answer that it
has. A new pair asks once more: a new version on **Versions**, or a changed picker on **Compare**. A pair also asks
once more when a later run adds a flipped task that its diff does not have, also after an ask that did not come. When a run is
deleted, from the Board or on the build machine, each page asks for its diffs again. A diff or a
reading that did not come is not asked for again by itself. **Versions** shows a dash in **Changed steps**, and
**Compare** shows "not kept". **Compare** asks once more when you change a picker, and every page asks
again when the Board starts again.

Each time you open the tab, it opens on **Live run** while a run goes. When no run goes, it opens on **Scoreboard**.

A difference between two arms is real only when it is larger than the noise. With n shared tasks, a difference under
about the square root of 2n tasks can come from chance (see [What the numbers mean](benchmarks.md#what-the-numbers-mean)).
The pages round the noise up to whole tasks, as `bench swe diff` does. With 50 tasks, the noise is 10 tasks. Each arm
has the same colour on every page. With fewer than 3 shared tasks, the pages say that nothing can be told yet, and
show what the runs have. A figure that a result did not keep shows "not kept", never 0. For example, a result kept
before the harness report was kept has no hidden tests, lint or size. A cost that cannot be priced shows "not priced".
Where a page has no data at all, it shows its section with "not kept" in place of the figure, and says nothing more.

**Scoreboard** reads the results of each arm from the runs that ended. The newest run of an arm sets its results key.
Each other run of the arm on that key adds the tasks that it has, so a short run after a long one keeps the other
tasks. The page judges the arms on the tasks that every arm graded (the shared tasks). **Compare**, **Task** and **Task
map** read the arms in the same way. An archived run is not in it.

- The verdict: the arm that resolves the most tasks, against Claude alone and against the next arm, judged against the
  noise. It also gives the cheapest arm for each resolved task, and how many fixes are clean. With one arm that has
  results, there is nothing to judge it against, and the verdict shows "not kept".
- Four figures: the most tasks resolved, with the change from the version before; the Conveyor arm's cost for each
  resolved task; its median minutes for each task; and the tasks that no arm resolves.
- **Leaderboard**: the arms in tiers. An arm is in the same tier as the leader of its tier when the difference is
  under the noise. Each row shows the resolved tasks, the 95% range of the resolve rate, the clean fixes, the tasks
  where the patch broke other tests, the cost for each resolved task, the median minutes and how often the arm fired.
  "From tokens" marks the cost of an agent arm, an estimate from its tokens. Click an arm to compare it with Conveyor.
- **Value: resolve rate against cost**: each arm's resolve rate, with its 95% range, against its cost for each task.
  A dashed line joins the arms that no other arm beats on both.
- **Hidden tests**: for each arm, a bar of its tasks by class: resolved, fixed but broke other tests, partial fix, no
  fix and no patch. A table gives the fail-to-pass tests that succeeded, the pass-to-pass tests that broke and the
  partial fixes.
- **Patch quality**: for the resolved tasks, the clean fixes, and the share of patches that are lint clean, at most
  twice the size of the reference fix, change a file that the reference fix does not change (strays), and prove the fix.
  Lint clean means no new pyflakes finding (ruff, rules F) in the Python files that the patch changes.
- **Lines of code**: the median code lines, test lines and files of the resolved patches, and their size against the
  reference fix.
- **Effort and steadiness**: the tokens for each fix, the sessions for each task, the review findings fixed and the fix
  rounds of a Conveyor arm, the tasks that reached the time limit, and the share of tasks run twice with the same
  result.
- **Where Conveyor loses tasks**: the first step where each task that the Conveyor arm did not resolve went wrong: the
  build, a review, a fix round, the test step, or a block. With no Conveyor arm in the runs, this box does not show.
- **What it agrees on**: the shared tasks by how many arms resolve them.
- **Next run to make**: the run that answers the biggest open question, with its cost and machine time ("not kept"
  where a result did not keep one), and each arm that did not always fire. **Plan this run** opens **Plan a run** with that run set.
- **Run history**: folded at the foot of the page. Each run, newest first, with what ran, its tasks, its state, its
  start and its cost. A run that you stopped shows "stopped at" and the number of tasks it reached, for example
  "stopped at 31". An archived run shows "archived". Tick runs to **Archive**, **Restore** or **Delete** them. With
  fewer than 3 shared tasks, the page keeps the same folded run history. With fewer than 3 shared tasks, the note on
  the patches says "All five made the same one-line fix" when every arm changed the same code files by the same
  lines, and shows "not kept" for the cost of the next run when a result did not keep it.

**Versions** compares the versions of the Conveyor arm in the order of their releases. A version named by a commit
comes after the releases. Each version reads its runs as **Scoreboard** reads an arm. The verdict judges the newest
version against the version before it, on the tasks that both versions ran. With fewer than 3 such tasks, no change
is past the noise, so the verdict says "inside the noise" and the table says "noise". With no such task, both say
"not kept". The verdict starts with "No regression." unless the newest version resolves fewer tasks by at least the
noise: then it gives the two counts and no such word. A chart shows the resolve rate of each
version with its 95% band, and a dashed line for Claude alone. A table gives each version's tasks and resolved count,
and its change from the version before on the tasks that both ran: better, worse, or noise. **Changed steps** shows,
for each version after the first, the steps whose engine files changed since the version before, whether a task
flipped or not. It shows a dash when no step changed, or when the page has not read them. The **Drift watch** compares the project's own cards before and after the last engine change
(see [Drift watch](benchmarks.md#drift-watch)). Each figure shows **Moved, better** or **Moved, worse** when the two
means are more than two standard errors apart, and **In its usual range** when they are not. It shows "not kept" when
a group has no spread for the figure, or fewer than 5 cards. The verdict's line about the belt names the figures that
moved past their usual range, and adds that the other figures stayed in it only when every figure is judged. When none moved, or the drift watch has not run, the line says "not kept". **Tasks that flipped** lists each task that one of the two newest versions resolved and
the other did not, with the first step where the two runs went apart. The page sends `bench swe diff` for
each version and the version before it, the newest first and one at a time: then each task shows the engine commits that
changed that step. `bench swe diff` reads the kept result of a task. A run with `--again` shows its own result, from another try, even when the outcome is the same. A task
where the result shown is that run's own, or where the two outcomes differ, shows "not kept" in place of its commits, also when no commit changed that step. With one version only, the page says
that no version can be compared yet; with none, the verdict says "not kept".

**Compare** sets any two arms, or an older version of any Conveyor arm of the study, against each other on the tasks that both graded. The
verdict says which one is better, when the difference is past the noise, and else how many tasks would show the
difference. When that is more than the tasks of the set, it gives the size of the set as the number and says that the
set has fewer, so treat the two as equal. A gap of 0 tasks is that case. With fewer than two arms that have results, or while the page has not read the two
sides, it says "not kept". With one shared task, which both resolved, the verdict says so; for any other result on fewer than 3 shared tasks it says "not kept". Four boxes put each task in one place: both resolve, only the first, only the second, or neither. They add
up to the shared tasks. **The flipped tasks** lists the tasks that only one resolved, with the first step where the two
runs went apart. The list shows at most 12 tasks. **Why, in short** has the model's reading of each flipped task, from
`bench swe diff`, which the page asks for by itself. The page marks it as the model's reading, not a fact. When
`bench swe diff` read another result of a task than the one shown (the result shown is a run with `--again`'s own),
or gave no reading, the task shows "not kept" in place of the reading. Click a flipped task to open it on **Task**.
**Cost and time** shows the cost, the cost for each resolved task, the machine time, the tokens and the sessions of the
two side by side. With fewer than 3 shared tasks it shows only the tokens, the minutes and the sessions.

**Live run** shows the run that goes now. The verdict says whether the run is on time and on budget against its
estimate, with the tasks done, the time left at this pace, the cost so far and the usage guard: the share of the week
that the guard has left, and the share that the rest of the run needs at the pace of its tasks so far. Both are "not
kept" for a run from before the engine kept them. A result that the run
reuses takes no time and costs nothing: the time left and the estimate count only the tasks that the run runs. A run
with `--again` reuses no result, so they count each of its tasks. Four figures give the same: the task runs done, the
time left at this pace, the cost spent so far, and **Not run**, the number of task runs that did not run. When there are
some, **Not run** has a chip with their causes and "tried again next run". **Tasks by arm** has a row for each task and a column for each arm: resolved, unresolved, not run, waiting, or
the step and minutes of the work now. **Score so far** gives each arm's resolved count on the tasks that every arm
graded, with its 95% range. A task that an arm did not run is left out for every arm. **Events** gives the last events of the run, newest first. **Stop the run** stops the
whole run: the work in progress and the tasks that it did not reach yet. Finished results stay. After you click it,
the button stays off until the build machine has ended the run and its containers. The page shows no answer to it, only a refusal. A
Stop names its run, so a late Stop never stops a newer run.
**Live run** in the page row shows the run that goes, or else the last run. When no run
goes, the page shows the last run: how it ended, and each arm's result, sessions, tokens, minutes and cost. A task
that has no grade shows "not kept", never unresolved. When the run did not start, or its process ended with no end
recorded, the verdict shows "not kept" for the end, and the run history shows its state ("did not start" or
"interrupted"). A run with no estimate to judge it by, or a figure that is not known, shows "not kept" in that place.

**Task** shows one task across every arm. Open it from **Compare**, **Versions**, **Task map** or **Live run**. The
verdict gives how many arms resolve the task, and what that says: no arm resolves it (look at the task first), every
arm does (it tells the arms apart only on cost and time), or some do. A table gives each arm's result, minutes, hidden
tests (for example "2 of 2 fail-to-pass · 41 of 41 pass-to-pass") and a note: the step where a Conveyor arm went wrong, or "did not fire" for another arm that did not fire.
**Conveyor's card, step by step** shows the card's steps as a bar: the width of each step is its time ("Width is time:
not kept" when the steps keep no time). **The review, in full** is folded. **This task over time** has a dot for each
run of the Conveyor arm on the task, by version. The facts give the repository, the difficulty, the size of the
reference fix and the task image, for example "4.1 GB, kept", or "not kept" for a result from before the engine kept
the size. Three buttons are under the facts:

- **Open the patch** shows the files of one patch, with the lines each file adds and removes: the Conveyor arm's, or
  the first arm's that kept one. Click it again to close it.
- **Open the logs** shows the end of the log that each arm kept for the task: the output of its run on the task. An
  arm that kept no log is left out. Click it again to close it.
- **Run this task again** queues a run of this one task on the arms that ran it, on the engine that they ran, as
  **Start the run** does, and shows no line when it starts. The run keeps its results apart from the saved
  ones, and does not replace them. When it ends, the Board reads its result of the task as the newest of each arm, so
  the pages and the Scoreboard show it. It stays off in these cases:
  - A run goes.
  - The task is not in the pinned order.
  - No arm reached the task.
  - The Conveyor arms ran the task on two engines, or on one that is not known: a run takes one engine.
  - The Board waits for the answer to an action that you sent.

  When it is off, a line under the buttons says why. When the build machine refuses the run, a line under the buttons
  gives the refusal.

  Only an admin can use it.

**Task map** shows all the tasks of SWE-bench Verified, grouped by repository, a square for each task. A square is
coloured by how many arms resolve the task, or by the result of one arm that you pick in **Colour by**. A grey square
has not run yet. Point at a square to see the task. Click a square to open the task on **Task**.

**Plan a run** starts with the question: **Does it work at all?** (5 tasks, the Conveyor arm), **Is one better than
another?** (50 tasks, Conveyor and Claude alone) or **Which arm gives the most per dollar?** (30 tasks, up to 6 ready
arms). The question sets the tasks and the arms. You can change both after that. **Arms** gives each arm's state
(**ready**, **changed**, **expired** or **checking**; "not kept" for an arm that has no check), its
cost and minutes for each task, and the results kept for it, which the run reuses at no cost. Every arm has a row.
An arm that the project does not offer shows "not kept" and has its box off. The **Tasks** slider sets
the number of tasks, and shows the smallest difference that this number can show. **Before you start** gives a
verdict on the size for your question, the cost at list prices, the machine time, the usual and worst-case sessions,
the kept results reused, the usage guard ("fits in the week left" or "would reach the guard; the run stops there", from
the share of the week left, the share at which the guard stops and the share that earlier runs used for each task: the
plan fits when it leaves more than the stop, and it fits whatever it uses when the guard is off; "not kept" when the share left is not kept,
or the arms have no guard, or, with the guard on, when no earlier run kept the share a task used), the container limits of the belt ("not kept" when they are not kept),
and the command that the run sends. **Start the run** sends that command,
with the engine's default settings. It stays off while a run goes, with no arm picked, while an arm that you picked is
not ready, while the usage guard holds an arm that you picked, and while an action that you sent has no answer yet.
**Check the arms first** runs the preflight of each arm that you picked and that is not ready. An arm that is being
checked gets no new preflight. When all the other arms that you picked are ready, it runs the preflight of each of them
again. It stays off with no arm picked, while all the arms that you picked are being checked, and
while an action that you sent has no answer yet. After a check, the Board reads the arms again, so the arms show their
new state, until a read answers and no arm is being checked. When a button is off, one line
under the buttons says why. The cost is an estimate: each session costs the mean of
this project's own priced card sessions, or of those on the arm's model when the arm has a model.

**Archive**, **Restore** and **Delete** are in the run history of **Scoreboard**.
An archived run keeps its records, and it is in no figure, **Compare** or plan. **Delete** asks for a second click,
which names the runs and says how many results stay because a run that you do not delete shows them. A run that has
not ended cannot be archived or deleted: stop it first.

The cost of a run, an arm or a task is its [cost at list prices](benchmarks.md#results), as the build machine
recorded it. A cost marked "estimate" is an agent arm's tokens, priced as input tokens at its model's list price, as
the agent reports no split by kind. A cost marked "partial" is a subtotal: only some of the work could be priced, so
the figure is not the whole cost of the run. The run history and the table of a finished run show both marks. "Not
priced" means that a session has no usage that can be priced. Runs from before costs were recorded are not priced,
never $0.

## Self-heals tab

The Self-heals tab shows the Self-heals list ([Harm or self-heals](cards.md#harm-or-self-heals)): real findings
whose failure heals by itself. A card waits longer, a step runs again, or text is wrong until the next turn. Conveyor
does not build them one by one. A batch card fixes the entries of an area together. With no entry, the tab says what
the list is for.

- **Title line**: on the right, a pill gives the days an entry stays on the list unseen, "An entry leaves after N
  days unseen". The days are the Rules setting **Self-heals expiry**, and **Rules › Self-heals** opens it. Under them,
  the time when the Board read the list. When a read fails, the tab keeps the last list and that time. Under it, for
  each project, when the sort of the queued follow-ups last ran and how many findings it moved to the lists, or that it
  has not run yet. The page shows this line also when the lists are empty.
- **What is a self-heal?**: under the title, closed until you click it. It says what a self-heal is, which kinds go
  to a follow-up card and which come to this list, why an entry gets no fix round, when an entry leaves the list, and
  why a finding seen in real logs is harm. A link opens [Harm or self-heals](cards.md#harm-or-self-heals).
- **Tiles**: **On the list**, with the issues and audits the entries come from. **Ready to batch**: the areas with 10
  entries or more. **Seen again, last 7 days**: a sighting starts the days of an entry again. **Leave in 7 days**: the
  entries that leave the list in 7 days or less. They stay in the dropped entries. **Moved up to harm, 30 days**: the entries moved up in the last 30 days, also those that a review found again later.
  Click **Seen again** or **Leave in 7 days** to show only the entries that the tile counts. The tile shows as
  pressed, and a line above the rows names the filter. Click **× clear** on that line, or click the tile again, to
  remove the tile filter. The search and the kind chip stay as they are. The tile filter works with the search, the sort and the kind chips. Click **Moved up to harm** to
  open the dropped entries with only the entries that the tile counts.
- **By area**: a card for each area, with the area's group and name, its count, and an age bar in three parts of the
  days. The legend gives each part's days. A screen reader reads the count of each part. The card also shows the
  kinds of its entries with their counts, "Ready to batch" at 10 entries or more, else "N more to batch", and
  **Review batch**, which opens the batch sheet for the area. An entry has the area of the file that its finding names
  ([Harm or self-heals](cards.md#harm-or-self-heals)). The **No area** card shows only when an entry has no area.
  Click a kind pill on an area card to show only the entries of that kind in that area. The pill shows as pressed,
  and so does the toolbar's chip of that kind when the toolbar has one. The line above the rows names the area and
  the kind. A pill and a tile do not filter together: a click on one ends the other. Click **× clear** on that line,
  or click the pill again, to show all entries. The filter works with the search and the sort. When **Show** picks
  another project, the filter ends.
- **Entries**: a search (finding, file or card), **Sort** (**Leaves soonest**, **Newest**, **Seen most**, **Area**)
  and a filter chip for each kind with its count: **Waits longer**, **Runs again**, **Text fixes itself**, **Extra
  work only**, **Docs or comment**, **Cleanup** and **Already guarded**. **All** shows the entries of every kind, in the tile filter when a tile is pressed. Each row shows the
  finding's level, its title, its kind, its file and line, its area, the issue it was found on (the card, for a card
  with no GitHub issue) and, when it was seen again, "seen N×". At the right, a ring and "N d left" show the days left. They are amber at 7 days or less. Under
  the list, "Showing N of M" and **Dropped entries (M)**, which opens the M entries that left the list, each with its
  file and line, why it left (expired after the days unseen, dropped by you, or moved up to harm), the judge's reason
  and the proof.
- **Detail panel**: click a row to show it beside the list. On a phone the panel is under the list. It shows the
  level, the kind, the days left, the area, the review that found it, the file (a link to the line), how often it
  was seen again, the judge's reason (**Why it self-heals**), the guard for an Already guarded entry (**Guarded by**),
  the **Proof** and the entry's history.
- **Move up to harm**: use it when the finding shows up in real logs or records. Click it, then click it again. The
  entry gets its own follow-up card at once and leaves the list. A card whose finding names a pipeline file is held
  for your yes, as a review follow-up is. **Drop now** takes the entry off the list now, and it
  stays in the dropped entries. Click it, then click it again. Check rows to act on many: the bar "N selected" has
  **File a batch card**, **Move up to harm** and **Clear**.
- **Docs**: the Docs list by area. Its entries do not expire, so they have no ring. Each row shows the finding's
  level, its title, its file and line, the issue it was found on, the judge's reason and the proof. **File docs sweep card** on an
  area opens the batch sheet for a docs sweep card of its entries.

### Batch sheet

The batch sheet files one card that fixes many entries together. It opens in place of the page from an area card's
**Review batch**, from **File a batch card** in the "N selected" bar, from **Add to the <area> batch** in the detail
panel and from **File docs sweep card** in the Docs section. From the bar, the sheet holds the rows you checked. It
has the label of the area with most of them. When you check rows of two projects, **File a batch card** is off, and
the bar says to check the entries of one project only.

- **Top**: the path **Self-heals list › group › area**, the title and **Cancel**, **File held** and **File and queue ·
  N entries**. **Cancel** and **Self-heals list** go back to the page.
- **Entries**: "Entries in this card N of M". Each entry has a checkbox, its id, level, title, kind, file and line,
  days left, for an audit's entry its "Fix:" line, and the judge's reason and the proof. Clear the checkbox to leave an entry out. The entry stays in
  the sheet, dimmed. **Keep all** keeps each entry again. **Add from other areas** lists the entries of the
  project's other areas. **Add** puts one in the card. An entry you leave out stays on the list with its days left.
- **The card**: its title, which you can edit. It starts as "Self-heals batch: <area> (N entries)", or "Docs sweep:
  <area> (N entries)", and follows the count until you edit it. **Priority** is P3 or P2. The card gets the area's
  label. **Files it touches** gives each file with the count of entries kept in it. **How this card is reviewed**
  says when an entry is done, and a note says what happens when the card lands or you shut it.

**File and queue** files the card with only the entries you keep, and the loop builds it in its turn, also when new
issues start in Held. **File held**
files it held: the loop does not build it until you release it. Click the button, then click it again. With
`followupissues` off in Rules, the card has no GitHub issue. Filed entries leave the list with the next read. An
entry whose card has not landed or closed waits for a later batch card, and the answer says so. When the build
machine refuses, the sheet stays open with its answer.

The kind of a Cleanup or Already guarded entry is the judge's. For a self-heals entry, the Board reads the kind from
the judge's reason. A reason that names no kind, or an entry with no date, shows "not read".

## Accounts

The Health panel shows the usage of every Claude account. The Rules tab sets which account a project's cards and
reviews use (`conveyor/README.md`, Accounts).
