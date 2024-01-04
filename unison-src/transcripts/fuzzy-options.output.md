# Test that the options selector for fuzzy finding is working as expected for different argument types.

If an argument is required but doesn't have a fuzzy resolver, the command should just print help.


```ucm
-- The second argument of move.term is a 'new-name' and doesn't have a fuzzy resolver
.> move.term

`move.term foo bar` renames `foo` to `bar`.

```
If a fuzzy resolver doesn't have any options available it should print a message instead of
opening an empty fuzzy-select.

```ucm
  ☝️  The namespace .empty is empty.

.empty> view

⚠️

Sorry, there are no options available to fuzzy select the
argument 'definition query', try providing all of the command's arguments.

`view foo` shows definitions named `foo` within your current
namespace.
`view` without arguments invokes a search to select definitions
to view, which requires that `fzf` can be found within your
PATH.
 
Supports glob syntax, where ? acts a wildcard, so `view List.?`
will show `List.map`, `List.filter`, etc, but not `List.map.doc`
(since ? only matches 1 name segment).

```
```unison
optionOne = 1

nested.optionTwo = 2
```

Definition args

```ucm
  ☝️  The namespace . is empty.

.> add

  ⍟ I've added these definitions:
  
    nested.optionTwo : ##Nat
    optionOne        : ##Nat

.> debug.fuzzy-options view _

  Select a definition:
    * optionOne
    * nested.optionTwo

```
Namespace args

```ucm
.> add

  ⊡ Ignored previously added definitions: nested.optionTwo
    optionOne

.> debug.fuzzy-options cd _

  Select a namespace:
    * nested

```
Project Branch args

```ucm
.> project.create-empty myproject

  🎉 I've created the project myproject.

  🎨 Type `ui` to explore this project's code in your browser.
  🔭 Discover libraries at https://share.unison-lang.org
  📖 Use `help-topic projects` to learn more about projects.
  
  Write your first Unison code with UCM:
  
    1. Open scratch.u.
    2. Write some Unison code and save the file.
    3. In UCM, type `add` to save it to your new project.
  
  🎉 🥳 Happy coding!

myproject/main> branch mybranch

  Done. I've created the mybranch branch based off of main.
  
  Tip: Use `merge /mybranch /main` to merge your work back into
       the main branch.

.> debug.fuzzy-options switch _

  Select a project or branch:
    * myproject/main
    * myproject/mybranch
    * myproject

```
