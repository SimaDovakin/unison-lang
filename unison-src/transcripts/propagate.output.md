# Propagating type edits

We introduce a type `Foo` with a function dependent `fooToInt`.

```unison
unique type Foo = Foo

fooToInt : Foo -> Int
fooToInt _ = +42
```

```ucm

  Loading changes detected in scratch.u.

  I found and typechecked these definitions in scratch.u. If you
  do an `add` or `update`, here's how your codebase would
  change:
  
    ⍟ These new definitions are ok to `add`:
    
      type Foo
      fooToInt : Foo -> Int

```
And then we add it.

```ucm
.subpath> add

  ⍟ I've added these definitions:
  
    type Foo
    fooToInt : Foo -> Int

.subpath> find.verbose

  1. -- #uj8oalgadr2f52qloufah6t8vsvbc76oqijkotek87vooih7aqu44k20hrs34kartusapghp4jmfv6g1409peklv3r6a527qpk52soo
     type Foo
     
  2. -- #uj8oalgadr2f52qloufah6t8vsvbc76oqijkotek87vooih7aqu44k20hrs34kartusapghp4jmfv6g1409peklv3r6a527qpk52soo#0
     Foo.Foo : Foo
     
  3. -- #j6hbm1gc2ak4f46b6705q90ld4bmhoi8etq2q45j081i9jgn95fvk3p6tjg67e7sm0021035i8qikmk4p6k845l5d00u26cos5731to
     fooToInt : Foo -> Int
     
  

.subpath> view fooToInt

  fooToInt : Foo -> Int
  fooToInt _ = +42

```
Then if we change the type `Foo`...

```unison
unique type Foo = Foo | Bar
```

```ucm

  Loading changes detected in scratch.u.

  I found and typechecked these definitions in scratch.u. If you
  do an `add` or `update`, here's how your codebase would
  change:
  
    ⍟ These names already exist. You can `update` them to your
      new definition:
    
      type Foo

```
and update the codebase to use the new type `Foo`...

```ucm
.subpath> update.old

  ⍟ I've updated these names to your new definition:
  
    type Foo

```
... it should automatically propagate the type to `fooToInt`.

```ucm
.subpath> view fooToInt

  ⚠️
  
  The following names were not found in the codebase. Check your spelling.
    fooToInt

```



🛑

The transcript failed due to an error in the stanza above. The error is:


  ⚠️
  
  The following names were not found in the codebase. Check your spelling.
    fooToInt

