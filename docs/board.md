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

- **Overview**: the panels Needs you, On the belt, Queue, Landed today, Declined, Health, Lanes, Cost and Metrics. The
  tab shows the Needs you count, "Overview · 4".
- **Control**: the loop's state, **Pause <project> after current**, **Stop now and requeue N cards**, the weekly limit
  bar, today's landed count and cost, and the cards in their columns. The machine head has **Pause all projects**.
- **Rules**: the settings.
- **Tests**: the project's test files.
- **Belt 3D**: the belt drawn as a conveyor line, each card on the track of its step (`conveyor/README.md`, Belt 3D).

A panel's head moves and collapses it. Customize shows or hides each panel and sets its width. It never hides Needs
you. **Restart the Board's feed** is in the Health panel.

**Show**, in the machine bar, picks the project that every tab shows.

## Needs you

- **Retry and Close.** Each blocked card has a **Retry** button (`conveyor.sh retry`) and a **Close** button. Close
  asks once, then closes the card's issue with a comment and shuts the card (`conveyor.sh shut`).
- **Build this and Close.** Each entry under "Pipeline changes held for you" has a **Build this** button, which releases
  the issue (`conveyor.sh control release`), and a **Close** button.

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
each card of the waiting list has **Build anyway**, which asks once and then sends `control force`.

Each card in the Held and Queue columns has **Depends on…**: type or pick open issues, or remove one (×). The host
writes the issue's `Depends on: #N` line on GitHub (`conveyor.sh control depends`). It refuses a self-dependency, an
issue that is not open, a cycle, or an issue whose card already runs.

## Push landed and Run full test suite

The Rules tab's **Push when a card lands** rule is On by default. Off, cards still land on main and nothing is pushed.

**Push landed** and **Run full test suite** are on the Control tab, which shows "N landed, not pushed". Push landed runs
the project's full test suite, the `test.full` of the pack (the project's settings, `.conveyor/project.json`), on
main. Green, it pushes the landed commits that the run tested.
Red, it pushes nothing: it runs each failed case alone and judges it. A case that passes alone goes on the flaky-test
record. A case that fails in the code becomes a P1 fix card. A case that fails for the machine or the network is
declined, with its reason. **Push anyway**, beside a red result, pushes those commits after a confirm. **Run full test
suite** runs the suite and pushes nothing. A project with no `test.full` shows both buttons greyed
(`conveyor/README.md`, The full test suite).

## Card steps

- A finished review reads "Review 2: passed" or "Review 2: changes asked". A review the judge read says "judge: N
  accepted, M declined".
- A fix session shows what started it: **Fix 2: review findings**, **Fix 1: reply check**, **Fix 3: main moved** or
  **Fix 4: tests failed**. Hover over the label for the full reason.
- A reply-check fix after the build shows on the Build step, "Build · reply check fix" and then "Build · reply check
  fixed". The Fix step shows the other fixes.
- A card in its Test step shows how many tests have run, "142 of 205 tests", and " · 2 failed" when any failed. A test
  command gives the count when it prints `TESTRUN cases=N`, and names each case as it ends with an empty file in
  `cases/ok` or `cases/failed` of its test log folder (`conveyor/README.md`, The test step). With no case count, the
  card shows its test files, "3 of 6 test files".

## Tests page

The Tests tab shows the project's test files: each file's CPU seconds, its median, its last runs and its status (Over
budget, Slower than usual, Waits, Flaky and others). A row opens to show its runs, to set a budget for the file or to
mark it slow on purpose (`conveyor.sh test-settings`). Test limits holds the Load limit (`maxLoad`, in the host file)
and the project's test budget (in the pack).

An opened row has the test actions. "now" runs at once and files no issue. "issue" files an issue. Judge this test and
Explain the slowdown need a model for the test actions ("Model for Tests actions"). Auto-file shows the test rules
(`conveyor.sh testrules`) and the log of what they filed (`conveyor/README.md`, Test actions).

## Accounts

The Health panel shows the usage of every Claude account. The Rules tab sets which account a project's cards and
reviews use (`conveyor/README.md`, Accounts).
