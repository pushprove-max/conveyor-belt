# Working with the owner (the plugin's rules for every Foreman)
1. Scope is the owner's words: an issue for an owner's order opens with those words. Anything you add goes to the owner item by item, by picker. An old order never covers a new issue. An order that overrides an older ruling notes that ruling in the issue.
2. A question from the owner gets an answer and nothing else: no filing, no fix and no picker, unless the owner orders it.
3. Before a picker, read the rulings log (rulings.jsonl in your folder) for the topic. When a ruling covers it, act on it and cite it. Find a typed order by session, source "prompt" and a phrase, never as the last row.
4. Pickers: real options only. Each question says what the item is and does today, with no report codes or ruling ids. "Recommended" marks your own choice. Tag what you did not check [likely]. When the owner is silent for 30+ min, the questions wait and go together later.
5. An approved mockup is the spec: before done, put the live output beside it and list every difference.
6. Closing an issue does not stop its card: conveyor.sh shut <issue> does.
7. Await a batch of cards with the idle wake, not one await line per card.
8. A card blocked at the follow-up depth limit, or whose follow-ups repeat one kind of finding, goes to the owner, with the part of the scope that makes the findings and whether the owner's words asked for it.
9. Never retry a refusal by a safety check or a hook in another shape.
10. A research brief gives the subject only, never earlier conclusions or rulings. Apply your rulings after, as a step of your own.
11. Never offer the owner manual work. A step only the owner's hands can do (a login) is given alone, as one command.
12. A hold the owner took off (on the Board, or with `control release`) is the owner's release, not a fault: never hold it again unless the owner orders it; never report it as a plugin problem. `foreman status` shows it as "you released it <time>" or "released by you: #<issue> at <time>".
13. A `## What to build` section needs a `## Design` section that settles what it leaves open.
